## ---------------------------------------------------------------------------
## Expand a minimal meteorological set to the full set lake models need.
##
## Ported from AEME::expand_met(). Behaviour differences, all deliberate:
##   * `tz` is explicit and is passed to calc_cc(), so cloud cover is
##     inferred against a correctly phased solar curve for local-time input.
##     AEME forces the session timezone to UTC and reads the wall clock.
##   * `MET_prsttn` / `MET_prmslp` are returned in Pa. AEME's
##     `estimate_station_pressure()` returned hPa although `MET_prsttn` is
##     documented as Pa, so a met set expanded without a supplied pressure
##     came out a factor of 100 low.
##   * Wind components use the meteorological convention (direction the wind
##     blows *from*, `uv2ds()` / `ds2uv()` mutually inverse). AEME swapped u
##     and v when deriving components from speed and direction.
##   * Columns are matched by exact `MET_*` name first, falling back to
##     AEME's substring matching.
##   * Base R only; works at any timestep, including hourly.
## ---------------------------------------------------------------------------

#' Pull one variable out of a met data frame by AEME token
#' @noRd
.met_col <- function(met, token) {
  nm <- paste0("MET_", token)
  if (nm %in% names(met)) return(met[[nm]])
  hit <- grep(token, names(met), fixed = TRUE)
  if (!length(hit)) return(NULL)
  met[[hit[1]]]
}

#' Expand a minimal meteorological set to a complete one
#'
#' Derives every variable a lake model may ask for from a small required
#' core, filling in only what is missing: relative humidity and dew point
#' from each other, vapour pressure, cloud cover from measured shortwave
#' ([calc_cc()]), downwelling longwave ([calc_in_lwr()]), station and sea
#' level pressure, wind speed/direction and u/v components, and snowfall.
#'
#' Required: `MET_radswd` (W m-2), `MET_tmpair` (degC), `MET_pprain` (mm per
#' timestep), one of `MET_humrel` (percent) / `MET_tmpdew` (degC), and wind
#' as either `MET_wndspd` (m/s) or both `MET_wnduvu` and `MET_wnduvv`.
#'
#' @param met data frame with a `Date` column (`Date` or POSIXct) and the
#'   `MET_*` columns above. Any timestep; nothing is resampled.
#' @param lat,lon lake position, decimal degrees.
#' @param elev lake surface elevation, m above sea level.
#' @param tz timezone the timestamps refer to, used for the solar geometry
#'   in [calc_cc()]. Default `"Etc/GMT-12"` (fixed NZST). Ignored when
#'   `MET_cldcvr` is supplied.
#' @param round_to decimal places for the returned values, or `NULL` to
#'   leave unrounded.
#'
#' @return data frame with `Date` and `MET_radswd`, `MET_radlwd`,
#'   `MET_cldcvr`, `MET_tmpair`, `MET_humrel`, `MET_tmpdew`, `MET_prvapr`,
#'   `MET_prsttn`, `MET_prmslp`, `MET_wndspd`, `MET_wnddir`, `MET_wnduvu`,
#'   `MET_wnduvv`, `MET_pprain`, `MET_ppsnow`.
#'
#' @examples
#' met <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 5),
#'                   MET_radswd = c(300, 120, 280, 90, 310),
#'                   MET_tmpair = c(18, 16, 19, 15, 20),
#'                   MET_humrel = c(70, 85, 65, 90, 60),
#'                   MET_wndspd = c(3, 5, 2, 6, 3),
#'                   MET_pprain = c(0, 12, 0, 25, 0))
#' expand_met(met, lat = -38.08, lon = 176.27, elev = 280)
#' @export
expand_met <- function(met, lat, lon, elev = 0, tz = "Etc/GMT-12",
                       round_to = 3) {

  stopifnot(is.data.frame(met), "Date" %in% names(met))
  Date <- met$Date
  n <- nrow(met)

  radswd <- .met_col(met, "radswd")
  tmpair <- .met_col(met, "tmpair")
  pprain <- .met_col(met, "pprain")
  miss <- c("MET_radswd", "MET_tmpair", "MET_pprain")[
    c(is.null(radswd), is.null(tmpair), is.null(pprain))]
  if (length(miss)) stop("required but not present: ", paste(miss, collapse = ", "))

  humrel <- .met_col(met, "humrel")
  tmpdew <- .met_col(met, "tmpdew")
  if (is.null(humrel) && is.null(tmpdew))
    stop("one of MET_humrel or MET_tmpdew is required, but neither is present")
  if (is.null(humrel)) humrel <- dewpoint_to_rh(tmpair, tmpdew)
  if (is.null(tmpdew)) tmpdew <- rh_to_dewpoint(tmpair, humrel)

  prvapr <- .met_col(met, "prvapr")
  if (is.null(prvapr)) prvapr <- vapour_pressure(tmpair, humrel)

  cldcvr <- .met_col(met, "cldcvr")
  if (is.null(cldcvr))
    cldcvr <- calc_cc(Date, airt = tmpair, swr = radswd, dewt = tmpdew,
                      lat = lat, lon = lon, elev = elev, tz = tz)

  ## ---- wind ------------------------------------------------------------
  wndspd <- .met_col(met, "wndspd")
  wnddir <- .met_col(met, "wnddir")
  wnduvu <- .met_col(met, "wnduvu")
  wnduvv <- .met_col(met, "wnduvv")
  if (is.null(wndspd)) {
    if (is.null(wnduvu) || is.null(wnduvv))
      stop("wind is required: supply MET_wndspd, or both MET_wnduvu and MET_wnduvv")
    ds <- uv2ds(wnduvu, wnduvv)
    wndspd <- ds[, "speed"]
    if (is.null(wnddir)) wnddir <- ds[, "dir"]
  }
  if (is.null(wnddir)) wnddir <- rep(180, n)
  if (is.null(wnduvu) || is.null(wnduvv)) {
    uv <- ds2uv(wnddir, wndspd)
    wnduvu <- uv[, "u"]; wnduvv <- uv[, "v"]
  }

  ## ---- pressure (Pa) ---------------------------------------------------
  prsttn <- .met_col(met, "prsttn")
  prmslp <- .met_col(met, "prmslp")
  if (is.null(prsttn) && is.null(prmslp)) {
    prsttn <- station_pressure(tmpair, humrel, elev = elev)
    prmslp <- mslp_from_station(prsttn, elev = elev, airt = tmpair)
  } else if (is.null(prsttn)) {
    prsttn <- station_from_mslp(prmslp, elev = elev, airt = tmpair)
  } else if (is.null(prmslp)) {
    prmslp <- mslp_from_station(prsttn, elev = elev, airt = tmpair)
  }

  radlwd <- .met_col(met, "radlwd")
  if (is.null(radlwd)) radlwd <- calc_in_lwr(cldcvr, tmpair, dewt = tmpdew)

  ppsnow <- .met_col(met, "ppsnow")
  if (is.null(ppsnow)) ppsnow <- rep(0, n)

  out <- data.frame(
    Date = Date,
    MET_radswd = radswd, MET_radlwd = radlwd, MET_cldcvr = cldcvr,
    MET_tmpair = tmpair, MET_humrel = humrel, MET_tmpdew = tmpdew,
    MET_prvapr = prvapr, MET_prsttn = prsttn, MET_prmslp = prmslp,
    MET_wndspd = wndspd, MET_wnddir = wnddir,
    MET_wnduvu = wnduvu, MET_wnduvv = wnduvv,
    MET_pprain = pprain, MET_ppsnow = ppsnow,
    row.names = NULL)
  if (!is.null(round_to)) out[-1] <- lapply(out[-1], round, round_to)
  out
}
