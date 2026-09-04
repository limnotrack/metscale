## ---------------------------------------------------------------------------
## Translate between the AEME `MET_*` meteorology scheme (see met_vars()) and
## the short variable names / units used by CMIP6, CORDEX and the CF
## conventions. `met_to_cf()` is the forward direction; `cf_to_met()` the
## inverse (the two round-trip).
## ---------------------------------------------------------------------------

## AEME MET_* <-> CF / CMIP short name, CF standard_name, CF-canonical unit.
.cf_map <- data.frame(
  met = c("MET_tmpair", "MET_tmpdew", "MET_humrel", "MET_prsttn", "MET_prmslp",
          "MET_prvapr", "MET_wndspd", "MET_wnddir", "MET_wnduvu", "MET_wnduvv",
          "MET_radswd", "MET_radlwd", "MET_cldcvr", "MET_pprain", "MET_ppsnow"),
  cf  = c("tas", "tdps", "hurs", "ps", "psl",
          "pvap", "sfcWind", "sfcWindDir", "uas", "vas",
          "rsds", "rlds", "clt", "pr", "prsn"),
  standard_name = c(
    "air_temperature", "dew_point_temperature", "relative_humidity",
    "surface_air_pressure", "air_pressure_at_mean_sea_level",
    "water_vapor_partial_pressure_in_air", "wind_speed", "wind_from_direction",
    "eastward_wind", "northward_wind",
    "surface_downwelling_shortwave_flux_in_air",
    "surface_downwelling_longwave_flux_in_air", "cloud_area_fraction",
    "precipitation_flux", "snowfall_flux"),
  unit = c("K", "K", "%", "Pa", "Pa",
           "Pa", "m s-1", "degree", "m s-1", "m s-1",
           "W m-2", "W m-2", "%", "kg m-2 s-1", "kg m-2 s-1"),
  stringsAsFactors = FALSE)

## forward per-variable unit conversion (AEME unit -> CF unit)
.cf_fwd <- list(
  MET_tmpair = function(x, dt) x + 273.15,
  MET_tmpdew = function(x, dt) x + 273.15,
  MET_prvapr = function(x, dt) x * 100,                 # hPa -> Pa
  MET_cldcvr = function(x, dt) x * 100,                 # fraction -> %
  MET_pprain = function(x, dt) x / dt,                  # mm/step -> kg m-2 s-1
  MET_ppsnow = function(x, dt) x / dt
)
## inverse (CF unit -> AEME unit)
.cf_bwd <- list(
  MET_tmpair = function(x, dt) x - 273.15,
  MET_tmpdew = function(x, dt) x - 273.15,
  MET_prvapr = function(x, dt) x / 100,
  MET_cldcvr = function(x, dt) x / 100,
  MET_pprain = function(x, dt) x * dt,
  MET_ppsnow = function(x, dt) x * dt
)

#' @noRd
.met_read_any <- function(x) {
  if (is.character(x) && length(x) == 1L && file.exists(x)) {
    x <- if (grepl("\\.rds$", x, ignore.case = TRUE)) readRDS(x)
         else utils::read.csv(x, check.names = FALSE, stringsAsFactors = FALSE)
  }
  as.data.frame(x, check.names = FALSE)
}

#' @noRd
.met_time_col <- function(df, want = c("date", "time", "datetime", "dt")) {
  hit <- names(df)[tolower(names(df)) %in% want]
  if (!length(hit)) hit <- names(df)[grepl("date|time", names(df), ignore.case = TRUE)]
  if (!length(hit)) stop("no date/time column found.", call. = FALSE)
  hit[1]
}

#' @noRd
.met_timestep_s <- function(tvec, timestep) {
  if (!is.null(timestep)) return(as.numeric(timestep))
  if (inherits(tvec, "Date")) {
    step <- stats::median(diff(as.numeric(tvec)), na.rm = TRUE) * 86400
  } else if (inherits(tvec, "POSIXt")) {
    step <- stats::median(diff(as.numeric(tvec)), na.rm = TRUE)
  } else {
    x <- as.character(tvec)
    p <- suppressWarnings(as.POSIXct(x, tz = "UTC", format = "%Y-%m-%d %H:%M:%S"))
    na <- is.na(p)
    if (any(na))
      p[na] <- suppressWarnings(as.POSIXct(x[na], tz = "UTC", format = "%Y-%m-%d"))
    step <- stats::median(diff(as.numeric(p)), na.rm = TRUE)
  }
  if (!is.finite(step) || step <= 0) NA_real_ else step
}

#' @noRd
.met_write <- function(out, time_name, outfile) {
  w <- out
  if (inherits(w[[time_name]], "POSIXt"))
    w[[time_name]] <- format(w[[time_name]], "%Y-%m-%d %H:%M:%S")
  utils::write.csv(w, outfile, row.names = FALSE)
}

#' Convert AEME `MET_*` meteorology to CF / CMIP variable names and units
#'
#' Renames the AEME `MET_*` columns ([met_vars()]) to the short variable
#' names used by CMIP6 / CORDEX and the CF conventions, and converts each to
#' its CF-canonical unit. `cf_to_met()` is the inverse.
#'
#' | AEME | CF / CMIP | CF standard_name | unit |
#' |------|-----------|------------------|------|
#' | `MET_tmpair` | `tas` | air_temperature | K |
#' | `MET_tmpdew` | `tdps` | dew_point_temperature | K |
#' | `MET_humrel` | `hurs` | relative_humidity | % |
#' | `MET_prsttn` | `ps` | surface_air_pressure | Pa |
#' | `MET_prmslp` | `psl` | air_pressure_at_mean_sea_level | Pa |
#' | `MET_prvapr` | `pvap` | water_vapor_partial_pressure_in_air | Pa |
#' | `MET_wndspd` | `sfcWind` | wind_speed | m s-1 |
#' | `MET_wnddir` | `sfcWindDir` | wind_from_direction | degree |
#' | `MET_wnduvu` | `uas` | eastward_wind | m s-1 |
#' | `MET_wnduvv` | `vas` | northward_wind | m s-1 |
#' | `MET_radswd` | `rsds` | surface_downwelling_shortwave_flux_in_air | W m-2 |
#' | `MET_radlwd` | `rlds` | surface_downwelling_longwave_flux_in_air | W m-2 |
#' | `MET_cldcvr` | `clt` | cloud_area_fraction | % |
#' | `MET_pprain` | `pr` | precipitation_flux | kg m-2 s-1 |
#' | `MET_ppsnow` | `prsn` | snowfall_flux | kg m-2 s-1 |
#'
#' Unit changes: air and dew-point temperature degC -> K; vapour pressure
#' hPa -> Pa; cloud cover fraction -> percent; precipitation and snowfall
#' "mm per timestep" -> a `kg m-2 s-1` flux (dividing by the timestep in
#' seconds - 1 mm of water over 1 m2 is 1 kg). Wind, radiation and the
#' surface/sea-level pressures are already in CF units and pass through
#' unchanged. Columns that are not `MET_*` (an id column, say) are carried
#' through untouched.
#'
#' @param met data frame with a date/time column plus `MET_*` columns, or a
#'   path to a `.csv` / `.rds` file holding one.
#' @param vars optional subset of `MET_*` columns to convert; default every
#'   mapped column present.
#' @param timestep seconds represented by one row, used only for the
#'   precipitation/snowfall flux conversion. `NULL` (default) infers it from
#'   the median spacing of the time column; pass it explicitly for an
#'   irregular series or a single row.
#' @param time_name name for the time column in the output. Default
#'   `"time"` (CF); pass `"Date"` to keep the AEME name.
#' @param outfile optional path; when given the result is written with
#'   `utils::write.csv(row.names = FALSE)` and returned invisibly.
#'
#' @return the data frame with CF short-name columns in CF units.
#'   Attributes `cf_units` and `cf_standard_names` (named by the output
#'   columns) and `timestep_s` record the conversion.
#'
#' @seealso [cf_to_met()] for the inverse, [met_vars()], [standardise_met()]
#'   and [guess_met_vars()] for bringing arbitrary names *to* `MET_*`.
#'
#' @examples
#' met <- data.frame(
#'   Date = seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 5),
#'   MET_tmpair = c(15, 15.4, 16, 16.2, 15.8),
#'   MET_wndspd = c(3, 4, 3.5, 5, 4.2),
#'   MET_pprain = c(0, 0.2, 1.1, 0, 0.4))
#' met_to_cf(met)
#' @export
met_to_cf <- function(met, vars = NULL, timestep = NULL,
                      time_name = "time", outfile = NULL) {
  df <- .met_read_any(met)
  if (!nrow(df)) stop("'met' has no rows.", call. = FALSE)
  tcol <- .met_time_col(df)

  map <- .cf_map
  present <- intersect(map$met, names(df))
  if (!is.null(vars)) present <- intersect(present, vars)
  if (!length(present))
    stop("no MET_* columns to convert", if (!is.null(vars)) " (after 'vars' filter)",
         ".", call. = FALSE)

  needs_dt <- any(c("MET_pprain", "MET_ppsnow") %in% present)
  dt <- if (needs_dt) .met_timestep_s(df[[tcol]], timestep) else NA_real_
  if (needs_dt && !is.finite(dt))
    stop("precipitation/snowfall need a timestep; the time column has < 2 ",
         "usable rows - pass 'timestep' (seconds).", call. = FALSE)

  out <- df
  names(out)[names(out) == tcol] <- time_name
  units <- stats::setNames(character(0), character(0))
  stdnm <- units
  for (v in present) {
    i  <- match(v, map$met)
    nm <- map$cf[i]
    x  <- out[[v]]
    if (!is.null(.cf_fwd[[v]])) x <- .cf_fwd[[v]](x, dt)
    out[[v]] <- x
    names(out)[names(out) == v] <- nm
    units[nm] <- map$unit[i]
    stdnm[nm] <- map$standard_name[i]
  }
  ## order: time first, converted vars in map order, then any carried columns
  ord <- c(time_name, map$cf[map$met %in% present],
           setdiff(names(out), c(time_name, map$cf[map$met %in% present])))
  out <- out[, ord, drop = FALSE]

  attr(out, "cf_units") <- units
  attr(out, "cf_standard_names") <- stdnm
  attr(out, "timestep_s") <- if (needs_dt) dt else NA_real_

  if (!is.null(outfile)) {
    .met_write(out, time_name, outfile)
    return(invisible(out))
  }
  out
}

#' Convert CF / CMIP meteorology back to the AEME `MET_*` scheme
#'
#' The inverse of [met_to_cf()]: renames `tas`, `pr`, `sfcWind`, ... to the
#' AEME `MET_*` names and converts units back (K -> degC, Pa -> hPa for
#' vapour pressure, percent -> fraction for cloud cover, `kg m-2 s-1` -> "mm
#' per timestep" for precipitation and snowfall). Unmapped columns pass
#' through.
#'
#' @param cf data frame with a time column plus CF/CMIP short-name columns,
#'   or a path to a `.csv` / `.rds` file.
#' @param vars optional subset of CF names to convert; default every mapped
#'   column present.
#' @param timestep seconds per row for the precipitation flux -> depth
#'   conversion; inferred from the time column when `NULL`.
#' @param time_name name for the time column in the output (default
#'   `"Date"`).
#' @param outfile optional output path (`utils::write.csv`).
#'
#' @return the data frame with `MET_*` columns in AEME units.
#' @seealso [met_to_cf()]
#' @examples
#' cf <- data.frame(time = seq(as.POSIXct("2024-01-01", tz = "UTC"),
#'                             by = "hour", length.out = 3),
#'                  tas = c(288.15, 288.55, 289.15), pr = c(0, 5.5e-5, 3e-4))
#' cf_to_met(cf)
#' @export
cf_to_met <- function(cf, vars = NULL, timestep = NULL,
                      time_name = "Date", outfile = NULL) {
  df <- .met_read_any(cf)
  if (!nrow(df)) stop("'cf' has no rows.", call. = FALSE)
  tcol <- .met_time_col(df, want = c("time", "date", "datetime", "dt"))

  map <- .cf_map
  present <- intersect(map$cf, names(df))
  if (!is.null(vars)) present <- intersect(present, vars)
  if (!length(present)) stop("no recognised CF/CMIP columns to convert.", call. = FALSE)

  needs_dt <- any(c("pr", "prsn") %in% present)
  dt <- if (needs_dt) .met_timestep_s(df[[tcol]], timestep) else NA_real_
  if (needs_dt && !is.finite(dt))
    stop("precipitation/snowfall need a timestep; pass 'timestep' (seconds).",
         call. = FALSE)

  out <- df
  names(out)[names(out) == tcol] <- time_name
  for (nm in present) {
    i <- match(nm, map$cf)
    v <- map$met[i]
    x <- out[[nm]]
    if (!is.null(.cf_bwd[[v]])) x <- .cf_bwd[[v]](x, dt)
    out[[nm]] <- x
    names(out)[names(out) == nm] <- v
  }
  keep <- c(time_name, map$met[map$cf %in% present])
  out <- out[, c(keep, setdiff(names(out), keep)), drop = FALSE]

  if (!is.null(outfile)) {
    .met_write(out, time_name, outfile)
    return(invisible(out))
  }
  out
}
