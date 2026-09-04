## ---------------------------------------------------------------------------
## Match arbitrary meteorological column names to the standard MET_* names
## and coerce values to the standard units.
##
## Ported from AEME::standardise_met(). Differences: name matching uses a
## self-contained synonym table (`guess_met_vars()`) rather than AEME's
## `key_naming` database, messaging is base R rather than cli, and the
## precipitation m -> mm detection threshold is tightened from 0.5 to 0.05
## so that it does not misfire on hourly data.
## ---------------------------------------------------------------------------

#' Standard meteorological variables, names and units
#'
#' @return data frame with `variable`, `name` and `unit` columns.
#' @examples
#' met_vars()
#' @export
met_vars <- function() {
  data.frame(
    variable = c("Shortwave radiation", "Longwave radiation", "Cloud cover",
                 "Air temperature", "Relative humidity", "Dew point temperature",
                 "Vapour pressure", "Station pressure", "Sea level pressure",
                 "Wind speed", "Wind direction", "Eastward wind", "Northward wind",
                 "Rainfall", "Snowfall"),
    name = c("MET_radswd", "MET_radlwd", "MET_cldcvr", "MET_tmpair",
             "MET_humrel", "MET_tmpdew", "MET_prvapr", "MET_prsttn",
             "MET_prmslp", "MET_wndspd", "MET_wnddir", "MET_wnduvu",
             "MET_wnduvv", "MET_pprain", "MET_ppsnow"),
    unit = c("W/m2", "W/m2", "fraction (0-1)", "degC", "%", "degC", "hPa",
             "Pa", "Pa", "m/s", "degrees (from)", "m/s", "m/s",
             "mm per timestep", "mm per timestep"),
    stringsAsFactors = FALSE)
}

#' Guess standard `MET_*` names from arbitrary column names
#'
#' Case-insensitive pattern matching against a built-in synonym table
#' covering common logger, council, NIWA/CliFlo, ERA5 and CMIP naming.
#'
#' @param x character vector of column names.
#' @return character vector the same length as `x`, holding the matched
#'   `MET_*` name or `NA` where nothing matched.
#' @examples
#' guess_met_vars(c("AirTemp_C", "WindSpd", "SolarRad", "junk"))
#' @export
guess_met_vars <- function(x) {
  pat <- c(
    MET_tmpdew = "(dew.?point|dewpt|dew.?temp|tdew|tmpdew|^d2m$)",
    MET_prmslp = "(sea.?level.?press|mslp|prmslp|^slp$)",
    MET_prvapr = "(vapour.?press|vapor.?press|prvapr)",
    MET_radswd = "(short.?wave|shortwv|swdown|sw.?rad|solar|rsds|ssrd|radswd|global.?rad)",
    MET_radlwd = "(long.?wave|lwdown|lw.?rad|rlds|strd|radlwd)",
    MET_cldcvr = "(cloud|cldcvr|cldfra|^tcc$|okta)",
    MET_humrel = "(rel.*hum|^rh$|humidity|humrel|hurs)",
    MET_wnddir = "(wind.?dir|^wdir$|wnddir)",
    MET_wnduvu = "(u.?wind|wind.?u|^uas$|^u10$|wnduvu|u.?comp)",
    MET_wnduvv = "(v.?wind|wind.?v|^vas$|^v10$|wnduvv|v.?comp)",
    MET_wndspd = "(wind.?spe|wind.?spd|^wspd$|windspeed|^ws$|wndspd|sfcwind|^wind$)",
    MET_tmpair = "(air.?temp|^tair$|temp.?air|^airt$|tmpair|dry.?bulb|^t2m$|^temp$|^temperature$|^t$)",
    MET_ppsnow = "(snow|ppsnow|^sf$)",
    MET_pprain = "(rain|precip|pprain|^tp$|^pr$)",
    ## last: a bare "press" only reaches here once sea level and vapour
    ## pressure have had their turn above
    MET_prsttn = "(press|barom|prsttn|^sp$|^psfc$|^ps$|^pres$)"
  )
  xl <- trimws(tolower(x))
  out <- rep(NA_character_, length(x))
  ## exact standard names win outright
  std <- met_vars()$name
  exact <- match(xl, tolower(std))
  out[!is.na(exact)] <- std[exact[!is.na(exact)]]
  for (nm in names(pat)) {
    hit <- is.na(out) & grepl(pat[[nm]], xl, perl = TRUE)
    out[hit] <- nm
  }
  out
}

#' @noRd
.nz_median <- function(x) {
  v <- x[is.finite(x) & x != 0]
  if (!length(v)) NA_real_ else stats::median(v)
}

#' Standardise meteorological names and units
#'
#' Renames columns to the standard `MET_*` names with [guess_met_vars()],
#' then detects and corrects common unit mistakes from the value ranges:
#' Kelvin to degC, hPa to Pa, humidity fraction to percent, oktas to
#' fraction, km/h to m/s, metres to millimetres, and MJ or kJ m-2 day-1 to
#' W m-2.
#'
#' @param met data frame with a date/time column and meteorological columns.
#' @param verbose report each rename and conversion.
#'
#' @return `met` with standard names and units, the time column renamed to
#'   `Date`. Unmatched columns are kept unchanged with a warning.
#'
#' @examples
#' raw <- data.frame(timestamp = as.Date("2024-01-01") + 0:4,
#'                   AirTemp_K = c(291, 289, 292, 288, 293),
#'                   WindSpd_kmh = c(11, 18, 7, 22, 11),
#'                   SolarRad = c(300, 120, 280, 90, 310),
#'                   Rain_mm = c(0, 12, 0, 25, 0))
#' standardise_met(raw)
#' @export
standardise_met <- function(met, verbose = TRUE) {
  stopifnot(is.data.frame(met))
  if (!nrow(met)) stop("'met' has no rows")
  say <- function(...) if (isTRUE(verbose)) message(...)

  ## ---- date column -----------------------------------------------------
  if (!"Date" %in% names(met)) {
    cand <- names(met)[tolower(names(met)) %in%
                         c("date", "datetime", "time", "timestamp", "dt")]
    if (!length(cand))
      cand <- names(met)[grepl("date|time", names(met), ignore.case = TRUE)]
    if (!length(cand)) stop("no date/time column found in 'met'")
    if (length(cand) > 1)
      warning("multiple date/time columns (", paste(cand, collapse = ", "),
              "); using ", cand[1])
    say("date column: ", cand[1], " -> Date")
    names(met)[names(met) == cand[1]] <- "Date"
  }

  ## ---- names -----------------------------------------------------------
  other <- setdiff(names(met), "Date")
  g <- guess_met_vars(other)
  dup <- duplicated(g) & !is.na(g)
  if (any(dup)) {
    warning("several columns matched the same variable; keeping the first: ",
            paste(other[dup], collapse = ", "))
    g[dup] <- NA_character_
  }
  if (any(is.na(g)))
    warning(sum(is.na(g)), " column(s) could not be matched and are left ",
            "unchanged: ", paste(other[is.na(g)], collapse = ", "))
  if (any(!is.na(g))) {
    say("renamed: ", paste(sprintf("%s -> %s", other[!is.na(g)], g[!is.na(g)]),
                           collapse = ", "))
    names(met)[match(other[!is.na(g)], names(met))] <- g[!is.na(g)]
  }

  required <- c("MET_radswd", "MET_tmpair", "MET_wndspd", "MET_pprain")
  if (length(setdiff(required, names(met))))
    warning("required variable(s) absent after renaming: ",
            paste(setdiff(required, names(met)), collapse = ", "))

  ## ---- units -----------------------------------------------------------
  cnv <- function(v, test, fun, from, to) {
    if (!v %in% names(met)) return(invisible())
    x <- met[[v]]
    if (all(is.na(x))) return(invisible())
    if (isTRUE(test(x))) {
      met[[v]] <<- fun(x)
      say(v, ": ", from, " -> ", to)
    }
  }
  for (v in c("MET_tmpair", "MET_tmpdew"))
    cnv(v, function(x) .nz_median(x) > 100, function(x) x - 273.15, "K", "degC")
  for (v in c("MET_prsttn", "MET_prmslp"))
    cnv(v, function(x) .nz_median(x) < 2000, function(x) x * 100, "hPa", "Pa")
  cnv("MET_prvapr", function(x) .nz_median(x) > 200, function(x) x / 100, "Pa", "hPa")
  cnv("MET_humrel", function(x) max(x, na.rm = TRUE) <= 1.5,
      function(x) x * 100, "fraction", "%")
  cnv("MET_cldcvr", function(x) max(x, na.rm = TRUE) > 1.5,
      function(x) x / 8, "oktas", "fraction")
  for (v in c("MET_wndspd", "MET_wnduvu", "MET_wnduvv"))
    cnv(v, function(x) abs(.nz_median(x)) > 35, function(x) x / 3.6, "km/h", "m/s")
  for (v in c("MET_pprain", "MET_ppsnow"))
    cnv(v, function(x) {
      mx <- max(x, na.rm = TRUE); is.finite(mx) && mx > 0 && mx < 0.05
    }, function(x) x * 1000, "m", "mm")
  for (v in c("MET_radswd", "MET_radlwd"))
    cnv(v, function(x) .nz_median(x) < 50, function(x) x / 0.0864,
        "MJ/m2/day", "W/m2")
  for (v in c("MET_radswd", "MET_radlwd"))
    cnv(v, function(x) .nz_median(x) > 5000, function(x) x / 86.4,
        "kJ/m2/day", "W/m2")

  ## ---- sanity ----------------------------------------------------------
  chk <- list(
    MET_tmpair = list(function(x) any(x < -90 | x > 60, na.rm = TRUE), "outside [-90, 60] degC"),
    MET_tmpdew = list(function(x) any(x < -90 | x > 60, na.rm = TRUE), "outside [-90, 60] degC"),
    MET_humrel = list(function(x) any(x < 0 | x > 100, na.rm = TRUE), "outside [0, 100] %"),
    MET_cldcvr = list(function(x) any(x < 0 | x > 1, na.rm = TRUE), "outside [0, 1]"),
    MET_radswd = list(function(x) any(x < 0, na.rm = TRUE), "negative values"),
    MET_radlwd = list(function(x) any(x < 0, na.rm = TRUE), "negative values"),
    MET_wndspd = list(function(x) any(x < 0, na.rm = TRUE), "negative values"),
    MET_wnddir = list(function(x) any(x < 0 | x > 360, na.rm = TRUE), "outside [0, 360] deg"),
    MET_pprain = list(function(x) any(x < 0, na.rm = TRUE), "negative values"),
    MET_ppsnow = list(function(x) any(x < 0, na.rm = TRUE), "negative values"),
    MET_prsttn = list(function(x) any(x < 80000 | x > 110000, na.rm = TRUE), "outside [80000, 110000] Pa"),
    MET_prmslp = list(function(x) any(x < 87000 | x > 108500, na.rm = TRUE), "outside [87000, 108500] Pa")
  )
  for (v in intersect(names(chk), names(met))) {
    x <- met[[v]]
    if (!all(is.na(x)) && isTRUE(chk[[v]][[1]](x)))
      warning(v, ": values ", chk[[v]][[2]], " - check the raw data or units")
  }
  met
}
