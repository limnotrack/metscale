## ---------------------------------------------------------------------------
## Cloud cover inferred from measured shortwave radiation.
##
## Ported from AEME::calc_cc() (originally gotmtools), which implements
## Martin & McCutcheon (1999). Changes:
##   * Hour angles are derived from the true UTC instant plus longitude,
##     rather than from a wall clock read under a forced UTC session
##     timezone against a local standard meridian. AEME's version is only
##     correct when the input is a `Date` or a UTC POSIXct; for a local
##     POSIXct (e.g. NZST) its potential-radiation curve is phase-shifted by
##     the UTC offset, biasing the inferred cloud cover.
##   * Base R only (no dplyr / tidyr / zoo / lubridate).
## ---------------------------------------------------------------------------

#' Hourly extraterrestrial radiation reaching the surface under clear sky
#'
#' Martin & McCutcheon (1999) potential radiation `Ho`, including the
#' atmospheric scattering/absorption transmission term.
#'
#' @param datetime POSIXct; the *end* of each hourly interval.
#' @param dewt dew point temperature, degC (drives the water-vapour path).
#' @param lat,lon decimal degrees.
#' @param elev elevation, m.
#' @return numeric vector, W m-2.
#' @noRd
.potential_radiation <- function(datetime, dewt, lat, lon, elev = 0) {
  Hsc <- 1390; cd <- 0.06; Rg <- 0.045
  p <- .utc_parts(datetime)
  yday <- p$yday
  ## true solar time (hours) and the hour angle at the start / end of the hour
  tst <- p$hour + lon / 15
  wrap <- function(a) {
    a <- (a + pi) %% (2 * pi) - pi                    # to (-pi, pi]
    a
  }
  he <- wrap((tst - 12) * pi / 12)
  hb <- wrap((tst - 13) * pi / 12)

  theta <- lat * .deg2rad
  r <- 1 + 0.017 * cos((2 * pi / 365) * (186 - yday))
  d <- 23.45 * .deg2rad * cos((2 * pi / 365) * (172 - yday))

  ## daylight mask: sun above the horizon at the middle of the interval
  wmid   <- atan2((sin(he) + sin(hb)) / 2, (cos(he) + cos(hb)) / 2)
  alpha1 <- sin(theta) * sin(d) + cos(theta) * cos(d) * cos(wmid)
  gamma  <- as.numeric(alpha1 > 0)

  Ho <- Hsc / r^2 *
    (sin(theta) * sin(d) +
       (12 / pi) * cos(theta) * cos(d) * (sin(he) - sin(hb))) * gamma

  ## atmospheric transmission
  a1abs  <- pmin(pmax(abs(alpha1), 1e-8), 1 - 1e-12)
  alpha  <- atan(a1abs / sqrt(1 - a1abs^2))
  theta_am <- ((288 - 0.0065 * elev) / 288)^5.256 /
    (sin(alpha) + 0.15 * ((alpha * .rad2deg) + 3.855)^(-1.253))

  Pwc <- 0.85 * exp(0.11 + 0.0614 * dewt)
  a2 <- exp(-(0.465 + 0.134 * Pwc) * (0.179 + 0.421 * exp(-0.721 * theta_am)) * theta_am)
  a1 <- exp(-(0.465 + 0.134 * Pwc) * (0.129 + 0.171 * exp(-0.88  * theta_am)) * theta_am)
  at <- (a2 + 0.5 * (1 - a1 - cd)) / (1 - 0.5 * Rg * (1 - a1 - cd))

  Ho <- at * Ho
  Ho[!is.finite(Ho) | Ho < 0] <- 0
  Ho
}

#' Estimate cloud cover from shortwave radiation
#'
#' Inverts the ratio of measured to clear-sky potential shortwave radiation
#' to a cloud fraction, following Martin & McCutcheon (1999). Works at any
#' timestep: daily input is evaluated on an internal hourly grid (built in
#' `tz`) and aggregated back to daily.
#'
#' @param datetime `Date` or POSIXct timestamps matching `swr`.
#' @param airt air temperature, degC.
#' @param swr measured downwelling shortwave radiation, W m-2.
#' @param relh relative humidity, percent; used when `dewt` is absent.
#' @param dewt dew point temperature, degC.
#' @param lat,lon decimal degrees.
#' @param elev elevation, m above sea level.
#' @param tz timezone that `datetime` refers to; used to expand daily dates
#'   into hours. Default `"Etc/GMT-12"` (fixed NZST).
#'
#' @return numeric vector of cloud cover fractions (0-1), same length as
#'   `datetime`. Values that cannot be inferred (measured shortwave at or
#'   above clear sky, or night) are linearly interpolated from neighbours.
#'
#' @examples
#' d <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 10),
#'                 airt = 18, swr = c(300, 120, 280, 90, 310, 150, 200, 260, 80, 290))
#' calc_cc(d$Date, airt = d$airt, swr = d$swr, relh = 70,
#'         lat = -38.08, lon = 176.27, elev = 280)
#' @export
calc_cc <- function(datetime, airt, swr, relh = NULL, dewt = NULL,
                    lat, lon, elev = 0, tz = "Etc/GMT-12") {

  n <- length(datetime)
  stopifnot(length(swr) == n)
  if (is.null(dewt)) {
    if (is.null(relh)) stop("supply either 'relh' or 'dewt'")
    dewt <- rh_to_dewpoint(rep_len(airt, n), rep_len(relh, n))
  }
  dewt <- rep_len(dewt, n)

  daily <- inherits(datetime, "Date") ||
    (n > 1 && stats::median(as.numeric(diff(as.POSIXct(datetime)),
                                       units = "hours"), na.rm = TRUE) >= 23)

  if (daily) {
    days <- as.Date(datetime)
    base <- as.POSIXct(paste0(format(days), " 00:00:00"), tz = tz)
    dt   <- rep(base, each = 24) + rep(seq_len(24) * 3600, times = n)  # hour-ending
    Ho   <- .potential_radiation(dt, rep(dewt, each = 24), lat, lon, elev)
    Ho   <- as.numeric(tapply(Ho, rep(seq_len(n), each = 24), mean))
  } else {
    Ho <- .potential_radiation(datetime, dewt, lat, lon, elev)
  }

  ## invert only where the ratio is physical (night and swr >= clear sky
  ## carry no cloud information); ifelse() would evaluate sqrt() on the
  ## negative elements too and warn
  cc <- rep(NA_real_, n)
  ok <- is.finite(Ho) & is.finite(swr) & Ho > 0 & swr < Ho
  cc[ok] <- sqrt((1 - swr[ok] / Ho[ok]) / 0.65)
  cc <- pmin(pmax(cc, 0), 1)

  ## fill gaps: interpolate interior, hold the ends
  good <- which(is.finite(cc))
  if (!length(good)) return(rep(0.5, n))
  if (length(good) > 1) {
    cc <- stats::approx(good, cc[good], xout = seq_len(n), rule = 2)$y
  } else {
    cc <- rep(cc[good], n)
  }
  pmin(pmax(cc, 0), 1)
}
