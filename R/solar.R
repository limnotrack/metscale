## ---------------------------------------------------------------------------
## Solar geometry and clear-sky shortwave.
##
## Ported from the GOTM airsea routines (solar_zenith_angle.F90,
## shortwave_radiation.F90) via AEME. Differences from the AEME versions:
##
##  * Time handling is explicit. GOTM's hour-angle term `(hh - 12)*15 + lon`
##    expects *UTC* hours, and these functions always evaluate it at the true
##    UTC instant of the timestamps you pass. AEME instead forces the session
##    timezone to UTC and reads the wall clock, which silently phase-shifts
##    the diurnal curve by the UTC offset (12 h for New Zealand) whenever the
##    input is a non-UTC POSIXct.
##  * Vectorised, base R only (no dplyr / lubridate).
## ---------------------------------------------------------------------------

.deg2rad <- pi / 180
.rad2deg <- 180 / pi

## UTC day-of-year and fractional hour for a vector of timestamps.
#' @noRd
.utc_parts <- function(datetime) {
  d <- as.POSIXct(datetime, tz = "UTC")
  list(yday = as.integer(format(d, "%j", tz = "UTC")),
       hour = as.numeric(format(d, "%H", tz = "UTC")) +
              as.numeric(format(d, "%M", tz = "UTC")) / 60)
}

#' Solar zenith angle
#'
#' GOTM `solar_zenith_angle.F90`. Evaluated at the true UTC instant of
#' `datetime`, so the result is independent of the `tzone` attribute.
#'
#' @param datetime POSIXct (or Date, treated as 00:00 UTC).
#' @param lat,lon position in decimal degrees.
#'
#' @return numeric vector of zenith angles in degrees; 90 when the sun is at
#'   or below the horizon.
#' @examples
#' t <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 24)
#' solar_zenith_angle(t, lat = -38.08, lon = 176.27)
#' @export
solar_zenith_angle <- function(datetime, lat, lon) {
  p <- .utc_parts(datetime)
  .szen(p$yday, p$hour, lat, lon)
}

## Zenith angle from integer day-of-year and fractional UTC hour.
#' @noRd
.szen <- function(yday, hour, lat, lon) {
  rlat <- lat * .deg2rad
  rlon <- lon * .deg2rad
  th0  <- 2 * pi * yday / 365.25
  decl <- 0.006918 - 0.399912 * cos(th0)       + 0.070257 * sin(th0) -
          0.006758 * cos(2 * th0) + 0.000907 * sin(2 * th0) -
          0.002697 * cos(3 * th0) + 0.001480 * sin(3 * th0)
  thsun  <- (hour - 12) * 15 * .deg2rad + rlon
  coszen <- sin(rlat) * sin(decl) + cos(rlat) * cos(decl) * cos(thsun)
  coszen[coszen < 0] <- 0
  .rad2deg * acos(pmin(pmax(coszen, -1), 1))
}

#' Clear-sky downwelling shortwave radiation
#'
#' GOTM `shortwave_radiation.F90`: Bird-type direct + diffuse beam under a
#' bulk atmospheric transmission, modulated by cloud fraction.
#'
#' @param datetime POSIXct (or Date, treated as 00:00 UTC).
#' @param lat,lon position in decimal degrees.
#' @param cloud cloud fraction, 0-1; scalar or vector (default 0 = clear sky).
#'
#' @return numeric vector, W m-2; zero at night.
#' @examples
#' t <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 24)
#' clear_sky_swr(t, lat = -38.08, lon = 176.27)
#' @export
clear_sky_swr <- function(datetime, lat, lon, cloud = 0) {
  p <- .utc_parts(datetime)
  .swr(.szen(p$yday, p$hour, lat, lon), p$yday, lat, cloud)
}

## Clear-sky irradiance from zenith angle (degrees) and day-of-year.
#' @noRd
.swr <- function(zenith, yday, lat, cloud = 0) {
  solar  <- 1350; tau <- 0.7; aozone <- 0.09
  eclips <- 23.439 * .deg2rad
  rlat   <- lat * .deg2rad

  ## acos() of a clamped cosine returns exactly 90 deg at night, whose
  ## cosine is ~6e-17 rather than 0 - round that away so night is truly dark
  coszen <- cos(zenith * .deg2rad)
  coszen[coszen <= 1e-8] <- 0
  qatten <- ifelse(coszen <= 0, 0, tau^(1 / pmax(coszen, 1e-8)))
  qzer   <- coszen * solar
  qdir   <- qzer * qatten
  qdiff  <- ((1 - aozone) * qzer - qdir) * 0.5
  qtot   <- qdir + qdiff

  ## solar noon altitude for this day-of-year (degrees)
  eqnx   <- (yday - 81) / 365 * 2 * pi
  sunbet <- asin(sin(rlat) * sin(eclips * sin(eqnx)) +
                 cos(rlat) * cos(eclips * sin(eqnx))) * .rad2deg

  q <- qtot * (1 - 0.62 * cloud + 0.0019 * sunbet)
  pmax(pmin(q, qtot), 0)
}

#' Estimate sub-daily shortwave radiation from daily means
#'
#' Builds a clear-sky irradiance curve from solar geometry and rescales it
#' so that each day's mean reproduces the supplied daily mean `MET_radswd`.
#' This preserves the observed daily energy while giving a physically
#' shaped diurnal cycle with genuine night-time zeros.
#'
#' Unlike the equivalent routine in `AEME`, timestamps are handled
#' explicitly: daily dates are expanded into sub-daily steps *in `tz`*, the
#' solar geometry is evaluated at the corresponding UTC instants, and the
#' result is returned labelled in `tz`. The shortwave peak therefore lands
#' at local solar noon rather than being offset by the UTC offset.
#'
#' @param met data frame with a `Date` column (class `Date`, or POSIXct at
#'   daily resolution) and `MET_radswd` in W m-2.
#' @param lat,lon position in decimal degrees.
#' @param tz timezone the daily dates refer to, and in which the sub-daily
#'   output is labelled. Default `"Etc/GMT-12"` (fixed NZST, no daylight
#'   saving).
#' @param timestep `"hour"` (default) or `"3hour"`.
#' @param interval what a timestamp denotes: `"ending"` (default) means the
#'   value is the mean over the interval *ending* at that label, which is
#'   the convention of ERA5 accumulated fluxes and hence of
#'   [extract_era5_hourly_met()]; `"beginning"` is the mean over the
#'   following interval; `"instant"` is the instantaneous value at the
#'   label. Averaging over an interval is done on a 10-minute sub-grid, so
#'   sunrise and sunset steps are handled correctly.
#' @param cloud optional cloud fraction, scalar or one value per row of
#'   `met`, used to damp the clear-sky curve before rescaling (the rescale
#'   makes the daily total insensitive to this, but it changes the shape
#'   slightly).
#'
#' @return data frame with `Date` (POSIXct in `tz`) and `MET_radswd`
#'   (W m-2). Days whose clear-sky mean is zero (polar night) return zeros.
#'
#' @examples
#' met <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day",
#'                              length.out = 5),
#'                   MET_radswd = c(300, 120, 280, 90, 310))
#' hr <- estimate_hourly_swr(met, lat = -38.08, lon = 176.27)
#' head(hr)
#' @export
estimate_hourly_swr <- function(met, lat, lon,
                                tz = "Etc/GMT-12",
                                timestep = c("hour", "3hour"),
                                interval = c("ending", "beginning", "instant"),
                                cloud = 0) {
  timestep <- match.arg(timestep)
  interval <- match.arg(interval)
  stopifnot(is.data.frame(met), "Date" %in% names(met),
            "MET_radswd" %in% names(met), is.numeric(lat), is.numeric(lon))

  step_h <- if (timestep == "hour") 1 else 3
  n_sub  <- 24 / step_h
  days   <- as.Date(met$Date)
  ## local-time sub-daily grid; POSIXct carries the matching UTC instants
  base   <- as.POSIXct(paste0(format(days), " 00:00:00"), tz = tz)
  dt     <- rep(base, each = n_sub) +
            rep(seq(0, 24 - step_h, by = step_h) * 3600, times = length(base))

  cloud <- if (length(cloud) == nrow(met)) rep(cloud, each = n_sub) else cloud[1]

  ## the clear-sky value the label stands for
  cs <- if (interval == "instant") {
    clear_sky_swr(dt, lat = lat, lon = lon, cloud = cloud)
  } else {
    ## mean over the interval, on a 10 minute sub-grid
    off <- seq(-step_h * 3600 + 300, 0, by = 600)
    if (interval == "beginning") off <- off + step_h * 3600
    sub <- vapply(off, function(o)
      clear_sky_swr(dt + o, lat = lat, lon = lon, cloud = cloud),
      numeric(length(dt)))
    rowMeans(sub)
  }

  ## rescale each day so the sub-daily mean matches the daily mean
  grp      <- rep(seq_along(base), each = n_sub)
  cs_daily <- as.numeric(tapply(cs, grp, mean))
  fac      <- ifelse(cs_daily > 0, met$MET_radswd / cs_daily, 0)
  out      <- cs * rep(fac, each = n_sub)

  data.frame(Date = dt, MET_radswd = pmax(out, 0))
}
