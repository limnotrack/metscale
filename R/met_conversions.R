## ---------------------------------------------------------------------------
## Elementary meteorological conversions: humidity, wind vectors, pressure,
## downwelling longwave. Ported from AEME (wind_helpers.R, calc_in_lwr.R,
## calc_humidity_vars.R, expand_met.R, utils.R), vectorised and with units
## made consistent - notably pressure is Pa everywhere, where AEME's
## `estimate_station_pressure()` returned hPa despite `MET_prsttn` being
## documented as Pa.
## ---------------------------------------------------------------------------

# ---- humidity --------------------------------------------------------------

#' Dew point temperature from air temperature and relative humidity
#'
#' Magnus-Tetens with the Alduchov & Eskridge coefficients (Lawrence 2005);
#' uncertainty about 0.35 degC.
#'
#' @param airt air temperature, degC.
#' @param relh relative humidity, percent (0-100).
#' @return dew point temperature, degC.
#' @examples
#' rh_to_dewpoint(20, 65)
#' @export
rh_to_dewpoint <- function(airt, relh) {
  lrh <- log(pmin(pmax(relh, 1e-3), 100) / 100)
  a <- lrh + (17.625 * airt) / (243.04 + airt)
  (243.04 * a) / (17.625 - a)
}

#' Relative humidity from air temperature and dew point
#'
#' @param airt air temperature, degC.
#' @param dewt dew point temperature, degC.
#' @return relative humidity, percent, capped at 100.
#' @examples
#' dewpoint_to_rh(20, 13.2)
#' @export
dewpoint_to_rh <- function(airt, dewt) {
  pmin(100, 100 * exp(17.625 * dewt / (243.04 + dewt)) /
             exp(17.625 * airt / (243.04 + airt)))
}

#' Actual vapour pressure
#'
#' Eqn. C2 of TVA (1972) as used in the DYRESM manual - the formulation
#' `AEME::expand_met()` uses for `MET_prvapr`.
#'
#' @param airt air temperature, degC.
#' @param relh relative humidity, percent.
#' @return vapour pressure, hPa.
#' @examples
#' vapour_pressure(20, 65)
#' @export
vapour_pressure <- function(airt, relh) {
  (relh / 100) * exp(2.303 * ((7.5 * airt / (airt + 237.3)) + 0.7858))
}

#' Humidity variables using the GOTM bulk formulation
#'
#' Vectorised port of `AEME::calc_humidity_vars()`: saturation and actual
#' vapour pressure, specific humidities and moist air density, from any of
#' four humidity inputs.
#'
#' @param hum humidity input, interpreted according to `hum_method`.
#' @param hum_method `1` relative humidity (percent), `2` wet-bulb
#'   temperature, `3` dew point temperature, `4` specific humidity (kg/kg).
#' @param airp air pressure, Pa.
#' @param tw water-surface temperature, degC (or K, auto-detected).
#' @param ta air temperature, degC (or K, auto-detected).
#' @param rgas gas constant for dry air, J/kg/K.
#' @param kelvin degC to K offset.
#' @param const06 ratio of molecular weights of water and dry air.
#'
#' @return list of numeric vectors: `es`, `qs`, `ea`, `qa`, `rhoa`.
#' @examples
#' calc_humidity_vars(hum = 70, hum_method = 1, airp = 101325,
#'                    tw = 18, ta = 15)
#' @export
calc_humidity_vars <- function(hum, hum_method = 1, airp, tw, ta,
                               rgas = 287.05, kelvin = 273.15,
                               const06 = 0.62198) {
  ## GOTM saturation vapour pressure polynomial (mbar, input degC)
  a <- c(6.107799961, 4.436518521e-1, 1.428945805e-2, 2.650648471e-4,
         3.031240396e-6, 2.034080948e-8, 6.136820929e-11)
  esat_mb <- function(tc)
    a[1] + tc * (a[2] + tc * (a[3] + tc * (a[4] + tc * (a[5] + tc * (a[6] + tc * a[7])))))
  to_c <- function(x) ifelse(x > 100, x - kelvin, x)

  tw_c <- to_c(tw); ta_c <- to_c(ta)

  es <- 0.98 * esat_mb(tw_c) * 100          # Pa, with salinity correction
  qs <- const06 * es / (airp - 0.377 * es)

  if (hum_method == 1) {
    ea <- (0.01 * hum) * esat_mb(ta_c) * 100
    qa <- const06 * ea / (airp - 0.377 * ea)
  } else if (hum_method == 2) {
    twet_c <- to_c(hum)
    ea <- esat_mb(twet_c) * 100
    ea <- ea - 6.6e-4 * (1 + 1.15e-3 * twet_c) * airp * (ta_c - twet_c)
    qa <- const06 * ea / (airp - 0.377 * ea)
  } else if (hum_method == 3) {
    ea <- esat_mb(to_c(hum)) * 100
    qa <- const06 * ea / (airp - 0.377 * ea)
  } else if (hum_method == 4) {
    qa <- hum
    ea <- qa * airp / (const06 + 0.378 * qa)
  } else {
    stop("hum_method must be 1 (RH), 2 (wet bulb), 3 (dew point) or 4 (specific humidity)")
  }

  rhoa <- airp / (rgas * (ta_c + kelvin) * (1 + const06 * qa))
  list(es = es, qs = qs, ea = ea, qa = qa, rhoa = rhoa)
}

# ---- wind ------------------------------------------------------------------

#' Wind vector components to speed and direction
#'
#' @param u,v eastward / northward wind components, m/s.
#' @return matrix with columns `dir` (degrees the wind blows *from*) and
#'   `speed` (m/s).
#' @examples
#' uv2ds(3, 4)
#' @export
uv2ds <- function(u, v) {
  d <- (270 - atan2(v, u) * 180 / pi) %% 360
  cbind(dir = d, speed = sqrt(u * u + v * v))
}

#' Wind speed and direction to vector components
#'
#' @param d direction the wind blows *from*, degrees.
#' @param s wind speed, m/s.
#' @return matrix with columns `u` (eastward) and `v` (northward), m/s.
#' @examples
#' ds2uv(225, 5)
#' @export
ds2uv <- function(d, s) {
  r <- (d %% 360) * pi / 180
  cbind(u = -s * sin(r), v = -s * cos(r))
}

#' Adjust wind speed from one measurement height to another
#'
#' Buoy and shore anemometers commonly sit 2--3 m above the surface, whereas
#' reanalyses (ERA5, ERA5-Land) and the lake-model convention report wind at
#' **10 m**. This rescales a wind-speed series to a different height,
#' assuming a neutrally-stratified surface layer.
#'
#' \describe{
#'   \item{`method = "log"`}{(default) the logarithmic wind profile,
#'     `u(z) = (u* / kappa) log(z / z0)`, so
#'     `u(to) = u(from) * log(to / z0) / log(from / z0)`. `z0` is the
#'     aerodynamic roughness length; the default `2e-4` m is a typical
#'     open-water value. `z0 = "charnock"` instead solves the
#'     Charnock relation `z0 = a u*^2 / g` (with `a = 0.013`) iteratively, so
#'     the adjustment grows with wind speed as a real sea/lake surface
#'     roughens.}
#'   \item{`method = "power"`}{the power law `u(to) = u(from) (to/from)^p`
#'     with `p = exponent` (default `0.11`, the open-water value; use about
#'     `1/7` over land).}
#' }
#' For 2 m -> 10 m over water all three give a factor of roughly 1.15--1.20.
#' The neutral-stability assumption is good for the moderate-to-strong winds
#' that matter for lake mixing; it over-corrects a little in very light,
#' stable conditions.
#'
#' @param u wind speed at height `from`, m/s (vector).
#' @param from measurement height of `u`, m.
#' @param to target height, m (default 10).
#' @param z0 roughness length in m for `method = "log"` (default `2e-4`), or
#'   the string `"charnock"` for a wind-speed-dependent open-water roughness.
#' @param method `"log"` (default) or `"power"`.
#' @param exponent power-law exponent for `method = "power"` (default 0.11).
#'
#' @return wind speed at height `to`, m/s, same length as `u`.
#' @seealso [met_wind_at_height()] to apply this to a `MET_*` data frame.
#' @examples
#' wind_at_height(5, from = 2)              # 2 m -> 10 m, ~5.9 m/s
#' wind_at_height(c(2, 6, 12), from = 3, to = 10)
#' wind_at_height(10, from = 2, z0 = "charnock")
#' @export
wind_at_height <- function(u, from, to = 10, z0 = 2e-4,
                           method = c("log", "power"), exponent = 0.11) {
  method <- match.arg(method)
  stopifnot(length(from) == 1L, length(to) == 1L, from > 0, to > 0)
  if (from == to) return(u)

  if (method == "power")
    return(u * (to / from)^exponent)

  if (is.character(z0) && z0 == "charnock") {
    kappa <- 0.41; g <- 9.81; a_ch <- 0.013
    z0v <- rep(1e-4, length(u))
    for (i in seq_len(25)) {
      ustar <- abs(u) * kappa / log(from / z0v)
      z0v   <- pmax(a_ch * ustar^2 / g, 1e-6)
    }
    return(u * log(to / z0v) / log(from / z0v))
  }

  z0 <- as.numeric(z0)
  stopifnot(z0 > 0, from > z0, to > z0)
  u * log(to / z0) / log(from / z0)
}

#' Adjust the wind columns of a met data frame to a new height
#'
#' Applies [wind_at_height()] to `MET_wndspd` and, when present, the
#' components `MET_wnduvu` / `MET_wnduvv` (scaled by the same factor, so wind
#' direction is unchanged). Use it to bring a 2 m buoy record onto the 10 m
#' convention before [fit_met_bias_correction()].
#'
#' @param met data frame with `MET_wndspd` and/or `MET_wnduvu` +
#'   `MET_wnduvv`.
#' @param from measurement height of the wind columns, m.
#' @param to,z0,method,exponent passed to [wind_at_height()].
#'
#' @return `met` with the wind columns rescaled, carrying
#'   `attr(., "wind_height") <- to`.
#' @seealso [wind_at_height()], [prepare_obs_met()] (which takes a
#'   `wind_height` argument).
#' @examples
#' d <- data.frame(Date = Sys.time() + 0:3 * 3600,
#'                 MET_wndspd = c(2, 4, 3, 5))
#' met_wind_at_height(d, from = 2)
#' @export
met_wind_at_height <- function(met, from, to = 10, z0 = 2e-4,
                               method = c("log", "power"), exponent = 0.11) {
  method <- match.arg(method)
  stopifnot(is.data.frame(met))
  wc <- intersect(c("MET_wndspd", "MET_wnduvu", "MET_wnduvv"), names(met))
  if (!length(wc)) stop("no MET_wndspd or MET_wnduvu/MET_wnduvv column.", call. = FALSE)

  spd <- if ("MET_wndspd" %in% wc) met$MET_wndspd
         else sqrt(met$MET_wnduvu^2 + met$MET_wnduvv^2)
  adj <- wind_at_height(spd, from = from, to = to, z0 = z0,
                        method = method, exponent = exponent)
  fac <- ifelse(is.finite(spd) & spd > 0, adj / spd, 1)
  for (v in wc) met[[v]] <- met[[v]] * fac
  attr(met, "wind_height") <- to
  met
}

# ---- pressure --------------------------------------------------------------

#' Station pressure from elevation
#'
#' Hypsometric equation using virtual temperature, i.e. accounting for the
#' moisture content of the air.
#'
#' @param airt air temperature, degC.
#' @param relh relative humidity, percent.
#' @param elev elevation, m above sea level.
#' @param mslp mean sea level pressure, Pa (default standard atmosphere).
#' @return station pressure, **Pa**.
#' @examples
#' station_pressure(15, 70, elev = 280)
#' @export
station_pressure <- function(airt, relh, elev, mslp = 101325) {
  g <- 9.80665; Rd <- 287.05; Rv <- 461.5
  mslp_hPa <- mslp / 100
  es <- 6.112 * exp((17.67 * airt) / (airt + 243.5))     # hPa
  e  <- (relh / 100) * es
  w  <- 0.622 * e / (mslp_hPa - e)
  Tv <- (airt + 273.15) * (1 + (Rv / Rd - 1) * w)
  mslp * exp(-g * elev / (Rd * Tv))
}

#' Convert between station and mean sea level pressure
#'
#' @param prsttn station pressure, Pa.
#' @param prmslp mean sea level pressure, Pa.
#' @param elev elevation, m.
#' @param airt air temperature, degC.
#' @return the converted pressure, Pa.
#' @examples
#' mslp_from_station(97300, elev = 280, airt = 15)
#' @export
mslp_from_station <- function(prsttn, elev, airt) {
  prsttn * (1 - (0.0065 * elev) / (airt + 273.15 + 0.0065 * elev))^-5.257
}

#' @rdname mslp_from_station
#' @export
station_from_mslp <- function(prmslp, elev, airt) {
  prmslp / (1 - (0.0065 * elev) / (airt + 273.15 + 0.0065 * elev))^-5.257
}

# ---- longwave --------------------------------------------------------------

#' Downwelling longwave radiation
#'
#' Clear-sky emissivity after Idso & Jackson with a cloud correction; the
#' formulation used by `AEME::calc_in_lwr()` (originally `gotmtools`).
#'
#' @param cc cloud cover fraction, 0-1.
#' @param airt air temperature, degC.
#' @param relh relative humidity, percent. Used to derive `dewt` when that
#'   is not supplied.
#' @param dewt dew point temperature, degC. Takes precedence over `relh`.
#'
#' @return downwelling longwave irradiance, W m-2.
#' @examples
#' calc_in_lwr(cc = 0.4, airt = 15, relh = 70)
#' @export
calc_in_lwr <- function(cc, airt, relh = NULL, dewt = NULL) {
  if (is.null(dewt)) {
    if (is.null(relh)) stop("supply either 'relh' or 'dewt'")
    dewt <- rh_to_dewpoint(airt, relh)
  }
  airt_K <- airt + 273.15
  ea <- 6.11 * 10^((7.5 * dewt) / (237.3 + dewt))        # hPa
  emiss_cs <- 0.23 + 0.433 * (ea / airt_K)^(1 / 8)
  tot_emiss <- emiss_cs * (1 - cc^2) + 0.976 * cc^2
  tot_emiss * 5.670373e-8 * airt_K^4
}
