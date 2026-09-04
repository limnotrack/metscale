## ---------------------------------------------------------------------------
## Read local daily CMIP6 / CCAM climate-projection netCDF at a point, decode
## the model calendar, and return AEME MET_* names / units. Feeds the
## delta-change step of ?scenario_workflow.
## ---------------------------------------------------------------------------

## CMIP short name -> AEME MET_* name (keys are lower case).
.cmip6_var_table <- c(
  tas     = "MET_tmpair",
  pr      = "MET_pprain",
  sfcwind = "MET_wndspd",
  rsds    = "MET_radswd",
  hurs    = "MET_humrel",
  rlds    = "MET_radlwd",
  ps      = "MET_prsttn"
)

#' Resolve a `vars` argument to a `cmip token -> MET_* name` vector
#' @noRd
.cmip6_var_map <- function(vars) {
  tbl <- .cmip6_var_table
  is_met <- grepl("^MET_", vars)
  if (any(is_met) && !all(is_met))
    stop("do not mix MET_* and CMIP short names in 'vars'.", call. = FALSE)
  if (all(is_met)) {
    bad <- setdiff(vars, tbl)
    if (length(bad))
      stop("no CMIP6 variable maps to: ", paste(bad, collapse = ", "), call. = FALSE)
    inv <- stats::setNames(names(tbl), unname(tbl))
    stats::setNames(vars, inv[vars])
  } else {
    v <- tolower(vars)
    bad <- setdiff(v, names(tbl))
    if (length(bad))
      stop("unknown CMIP6 variable(s): ", paste(bad, collapse = ", "), call. = FALSE)
    stats::setNames(unname(tbl[v]), v)
  }
}

#' Split `<variable>_<experiment>_*.nc` file names
#' @noRd
.cmip6_file_info <- function(files) {
  parts <- strsplit(sub("\\.nc$", "", basename(files)), "_")
  data.frame(
    file       = files,
    var        = vapply(parts, function(p) p[1], character(1)),
    experiment = vapply(parts, function(p) if (length(p) >= 2) p[2] else NA_character_,
                        character(1)),
    stringsAsFactors = FALSE)
}

#' Decode a CF "<unit> since <origin>" time axis, honouring the model calendar
#'
#' `365_day`/`noleap`, `360_day` and `366_day`/`all_leap` use fixed month
#' lengths and are mapped onto real `Date`s (a `365_day` series therefore has
#' no 29 February). `standard`/`gregorian`/`proleptic_gregorian` use the real
#' civil calendar.
#' @noRd
.cmip6_time_to_date <- function(tvals, units, calendar = "standard") {
  m <- regmatches(units, regexec("([A-Za-z]+)\\s+since\\s+(.+)", units))[[1]]
  if (length(m) != 3L) stop("cannot parse time units: ", units, call. = FALSE)
  per_day <- c(day = 1, days = 1, hour = 24, hours = 24,
               minute = 1440, minutes = 1440,
               second = 86400, seconds = 86400)[[tolower(m[2])]]
  day_off <- as.numeric(tvals) / per_day
  o <- as.integer(strsplit(substr(trimws(m[3]), 1, 10), "[-/]")[[1]])

  cal <- tolower(calendar %||% "standard")
  if (cal %in% c("", "standard", "gregorian", "proleptic_gregorian", "julian"))
    return(as.Date(sprintf("%04d-%02d-%02d", o[1], o[2], o[3])) + day_off)

  ylen <- if (cal %in% c("360_day", "360")) 360L
          else if (cal %in% c("366_day", "all_leap")) 366L
          else 365L                                   # 365_day / noleap
  mlen <- if (ylen == 360L) rep(30L, 12)
          else if (ylen == 366L) c(31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
          else c(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
  cum <- c(0L, cumsum(mlen))
  origin_abs <- o[1] * ylen + cum[o[2]] + (o[3] - 1L)
  abs_day <- as.integer(round(origin_abs + day_off))
  yr  <- abs_day %/% ylen
  rem <- abs_day %% ylen
  mo  <- findInterval(rem, cum[-13L])
  dy  <- rem - cum[mo] + 1L

  ## a fixed-length calendar can carry days that the real civil calendar
  ## lacks (29-30 Feb, a 31st in a 30-day month); clamp those onto the last
  ## real day of the month so the series stays gap-free and month-aligned
  leap <- (yr %% 4L == 0L) & ((yr %% 100L != 0L) | (yr %% 400L == 0L))
  real_mlen <- matrix(c(31L, 28L, 31L, 30L, 31L, 30L, 31L, 31L, 30L, 31L, 30L, 31L),
                      nrow = length(yr), ncol = 12L, byrow = TRUE)
  real_mlen[leap, 2L] <- 29L
  dy <- pmin(dy, real_mlen[cbind(seq_along(mo), mo)])
  as.Date(sprintf("%04d-%02d-%02d", yr, mo, dy))
}

#' Convert one variable's values to AEME units from its netCDF `units` string
#' @noRd
.cmip6_convert <- function(x, met_name, units) {
  u <- tolower(trimws(units %||% ""))
  if (met_name %in% c("MET_tmpair", "MET_tmpdew")) {
    if (u %in% c("k", "kelvin")) return(x - 273.15)
    return(x)
  }
  if (met_name %in% c("MET_pprain", "MET_ppsnow")) {
    if (grepl("kg.*m-?\\*?\\*?-?2.*s-?\\*?\\*?-?1|kg/m2/s", u)) return(x * 86400)
    if (u %in% c("m", "metre", "meter")) return(x * 1000)
    return(x)                                          # mm/day, mm, mm day-1
  }
  x
}

#' Bilinear / nearest sample of a \[lon, lat, time\] (in any dim order) array
#' @noRd
.cmip6_interp <- function(arr, dim_names, gx, gy, lon, lat, method) {
  li <- which(dim_names %in% c("longitude", "lon", "x"))
  la <- which(dim_names %in% c("latitude", "lat", "y"))
  ti <- which(dim_names %in% c("time", "Time", "t"))
  arr <- aperm(arr, c(li, la, ti))                     # -> [lon, lat, time]

  if (length(gy) > 1 && gy[2] < gy[1]) {               # store latitude ascending
    gy  <- rev(gy)
    arr <- arr[, rev(seq_along(gy)), , drop = FALSE]
  }
  if (method == "nearest") {
    ix <- which.min(abs(gx - lon))
    iy <- which.min(abs(gy - lat))
    return(as.numeric(arr[ix, iy, ]))
  }
  ix <- findInterval(lon, gx, all.inside = TRUE)
  iy <- findInterval(lat, gy, all.inside = TRUE)
  fx <- (lon - gx[ix]) / (gx[ix + 1L] - gx[ix])
  fy <- (lat - gy[iy]) / (gy[iy + 1L] - gy[iy])
  as.numeric(
    (1 - fx) * (1 - fy) * arr[ix,      iy,      ] +
         fx  * (1 - fy) * arr[ix + 1L, iy,      ] +
    (1 - fx) *      fy  * arr[ix,      iy + 1L, ] +
         fx  *      fy  * arr[ix + 1L, iy + 1L, ])
}

#' Read one single-variable projection file to a `data.frame(Date, value)`
#' @noRd
.cmip6_read_file <- function(f, met_name, lon, lat, method, calendar) {
  nc <- ncdf4::nc_open(f)
  on.exit(ncdf4::nc_close(nc))
  vn <- names(nc$var)[1]
  dim_names <- vapply(nc$var[[vn]]$dim, `[[`, character(1), "name")

  lon_name <- intersect(c("longitude", "lon", "x"), names(nc$dim))[1]
  lat_name <- intersect(c("latitude", "lat", "y"), names(nc$dim))[1]
  time_name <- intersect(c("time", "Time", "t"), names(nc$dim))[1]
  if (is.na(lon_name) || is.na(lat_name) || is.na(time_name))
    stop(basename(f), ": could not find longitude / latitude / time dimensions.",
         call. = FALSE)

  gx  <- as.numeric(nc$dim[[lon_name]]$vals)
  gy  <- as.numeric(nc$dim[[lat_name]]$vals)
  arr <- ncdf4::ncvar_get(nc, vn, collapse_degen = FALSE)
  val <- .cmip6_interp(arr, dim_names, gx, gy, lon, lat, method)

  tv  <- ncdf4::ncvar_get(nc, time_name)
  tu  <- ncdf4::ncatt_get(nc, time_name, "units")$value
  cal <- if (identical(calendar, "auto")) {
    a <- ncdf4::ncatt_get(nc, time_name, "calendar")$value
    if (is.character(a) && nzchar(a)) a else "standard"
  } else calendar
  dates <- .cmip6_time_to_date(tv, tu, cal)

  vu  <- ncdf4::ncatt_get(nc, vn, "units")$value
  data.frame(Date = dates, value = .cmip6_convert(val, met_name, vu))
}

#' Extract daily CMIP6 / CCAM projection meteorology for a point
#'
#' Reads local daily climate-projection netCDF files - one variable per file,
#' as produced by the NIWA CCAM downscaling of CMIP6 - samples them at a
#' point, decodes the model calendar to real dates, and returns the series in
#' AEME `MET_*` names and units. Built for the delta-change step of
#' [scenario_workflow]: extract the model *historical* and *future* series
#' with this function, form monthly change factors, and apply them to a
#' [bias_correct_daily_baseline()].
#'
#' Files are matched by the convention `<variable>_<experiment>_*.nc` (for
#' example `tas_ssp245_NorESM2-MM_CCAM_daily_NZ5km_bc.nc` -> variable `tas`,
#' experiment `ssp245`). Recognised variables and their AEME targets:
#' `tas` -> `MET_tmpair`, `pr` -> `MET_pprain`, `sfcWind` -> `MET_wndspd`,
#' `rsds` -> `MET_radswd`, `hurs` -> `MET_humrel`, `rlds` -> `MET_radlwd`,
#' `ps` -> `MET_prsttn`.
#'
#' Units are converted from each file's own `units` attribute: Kelvin ->
#' degC, `kg m-2 s-1` -> mm day-1, metres -> mm. Everything else is passed
#' through (the CCAM `pr` files are already mm day-1). `_FillValue` is applied
#' by \pkg{ncdf4}.
#'
#' @param path directory holding the `.nc` files, or a character vector of
#'   file paths.
#' @param lon,lat point of interest, decimal degrees (WGS84).
#' @param vars variables to return, as AEME `MET_*` names or CMIP short names
#'   (do not mix the two). Default is the seven mapped variables; only those
#'   present on disk are returned.
#' @param experiments optional character vector to keep (e.g.
#'   `c("historical", "ssp245")`); `NULL` (default) returns every experiment
#'   found.
#' @param method `"bilinear"` (default) interpolation between the four
#'   surrounding grid nodes, or `"nearest"` grid node.
#' @param calendar `"auto"` (default, read from the `time` variable's
#'   `calendar` attribute), or force one of `"365_day"`, `"360_day"`,
#'   `"366_day"`, `"standard"`. A `365_day` / `360_day` series is mapped onto
#'   real dates, so it has no 29 February (and, for `360_day`, no 31st).
#' @param tz time zone recorded on the result; the series is daily and
#'   carries no time of day. Default `"Etc/GMT-12"`.
#' @param verbose print each file as it is read.
#'
#' @return a data frame with `Date` (class `Date`), `experiment` (character)
#'   and one column per requested variable - stacked over experiments, wide
#'   over variables. Attributes `lon`, `lat`, `method`, `tz`.
#'
#' @seealso [scenario_workflow], [bias_correct_daily_baseline()],
#'   [disaggregate_met_to_hourly()]
#'
#' @examples
#' \dontrun{
#' cmip <- extract_cmip6_point("inst/extdata/rotorua_cmip6",
#'                             lon = 176.2717, lat = -38.0790)
#' split(cmip, cmip$experiment) |> lapply(head, 2)
#' }
#' @export
extract_cmip6_point <- function(path, lon, lat,
                                vars = c("MET_tmpair", "MET_pprain",
                                         "MET_wndspd", "MET_radswd",
                                         "MET_humrel", "MET_radlwd",
                                         "MET_prsttn"),
                                experiments = NULL,
                                method = c("bilinear", "nearest"),
                                calendar = c("auto", "365_day", "360_day",
                                             "366_day", "standard"),
                                tz = "Etc/GMT-12",
                                verbose = TRUE) {

  method   <- match.arg(method)
  calendar <- match.arg(calendar)
  if (!requireNamespace("ncdf4", quietly = TRUE))
    stop("Package 'ncdf4' is required.", call. = FALSE)
  stopifnot(length(lon) == 1L, length(lat) == 1L,
            is.numeric(lon), is.numeric(lat))
  say <- function(...) if (isTRUE(verbose)) message(...)

  files <- if (length(path) == 1L && dir.exists(path))
    list.files(path, pattern = "\\.nc$", full.names = TRUE) else path
  files <- files[file.exists(files)]
  if (!length(files)) stop("no .nc files found at 'path'.", call. = FALSE)

  map  <- .cmip6_var_map(vars)
  info <- .cmip6_file_info(files)
  info <- info[tolower(info$var) %in% names(map) & !is.na(info$experiment), ,
               drop = FALSE]
  if (!is.null(experiments))
    info <- info[info$experiment %in% experiments, , drop = FALSE]
  if (!nrow(info))
    stop("no files matched the requested 'vars' / 'experiments'.", call. = FALSE)

  out <- lapply(unique(info$experiment), function(ex) {
    sub <- info[info$experiment == ex, , drop = FALSE]
    say(ex, ":")
    frames <- lapply(seq_len(nrow(sub)), function(i) {
      met <- unname(map[tolower(sub$var[i])])
      d <- .cmip6_read_file(sub$file[i], met, lon, lat, method, calendar)
      say("  ", basename(sub$file[i]), " -> ", met, " (", nrow(d), " days)")
      stats::setNames(d, c("Date", met))
    })
    m <- Reduce(function(a, b) merge(a, b, by = "Date", all = TRUE), frames)
    m <- m[order(m$Date), , drop = FALSE]
    data.frame(Date = m$Date, experiment = ex,
               m[setdiff(names(m), "Date")], check.names = FALSE,
               row.names = NULL)
  })

  res <- do.call(rbind, out)
  rownames(res) <- NULL
  attr(res, "lon") <- lon
  attr(res, "lat") <- lat
  attr(res, "method") <- method
  attr(res, "tz") <- tz
  res
}
