#' Extract hourly ERA5-Land meteorology for a point or lake
#'
#' Reads monthly hourly ERA5-Land netCDF files from `path`, pulls a time
#' series for a location, de-accumulates the flux variables, converts
#' everything to standard lake-model units ([met_vars()]), shifts the time
#' stamps from UTC to `tz` and returns a tidy wide data frame ready to be
#' written to CSV.
#'
#' Files are located with `file_template`, which defaults to the naming the
#' LERNZmp download scripts produce,
#' `nz_era5-land_<YYYY>_<MM>_<variable>_daily.nc` - note the data are hourly
#' despite the `_daily` suffix.
#'
#' The location can be given as
#'   * `lon` / `lat` scalars, or
#'   * `geom` - an `sf`/`sfc` point or polygon in any CRS.
#'
#' Spatial sampling (`method`):
#'   * `"nearest"`  - value of the single closest grid node to the point
#'                    / polygon centroid.
#'   * `"bilinear"` - bilinear interpolation between the four grid nodes
#'                    surrounding the point / centroid.
#'   * `"area"`     - area-weighted mean of every ERA5 grid cell whose
#'                    footprint overlaps the polygon (use when a lake
#'                    straddles several cells). Weights are intersection
#'                    areas computed in the `area_crs` projection.
#'   * `"area_mean"`- unweighted mean of the overlapping cells.
#' `"area"` / `"area_mean"` require a polygon `geom`; they fall back to
#' `"bilinear"` for a point or a lake smaller than one grid cell.
#'
#' Unit handling:
#'   * 2m_temperature / 2m_dewpoint_temperature   K            -> degC
#'   * 10m_u/v_component_of_wind                  m s-1        -> m s-1 (unchanged)
#'   * surface_pressure                           Pa           -> Pa   (or hPa)
#'   * surface_solar_radiation_downwards (ssrd)   J m-2 accum. -> W m-2
#'   * surface_thermal_radiation_downwards (strd) J m-2 accum. -> W m-2
#'   * total_precipitation (tp)                   m accum.     -> mm hr-1 (or m day-1)
#'   * snowfall (sf)                              m accum.     -> mm hr-1 (or m day-1)
#'
#' ERA5-Land accumulations run from 00:00 UTC and reset at 01:00 UTC each
#' day, so the hourly amount is recovered as a first difference except at
#' the 01:00 UTC step (and the first record), where the stored value is
#' already the hourly amount.
#'
#' @param path   directory holding the ERA5-Land netCDF files.
#' @param file_template `sprintf()` template for the file names, taking the
#'   year (integer), month (integer) and ERA5 variable name in that order.
#'   Default `"nz_era5-land_%d_%02d_%s_daily.nc"`.
#' @param area_crs projected CRS (EPSG code or WKT) used to compute polygon
#'   intersection areas for `method = "area"`. Default `2193` (NZTM 2000);
#'   use a projection appropriate to your region.
#' @param lon,lat point of interest, decimal degrees (WGS84). Ignored if
#'   `geom` is supplied.
#' @param geom   an `sf`/`sfc` point or polygon (any CRS) identifying the
#'   location; overrides `lon`/`lat`.
#' @param years  integer vector of years to read. `NULL` (default) uses
#'   every year found on disk for the requested variables.
#' @param months integer vector of months to read (default `1:12`).
#' @param variables ERA5-Land variable names to read. Defaults to the nine
#'   standard meteorological forcing variables.
#' @param method  `"nearest"`, `"bilinear"` (default), `"area"` or
#'   `"area_mean"` - see Details.
#' @param tz      output time zone. Default `"Etc/GMT-12"` = fixed NZST
#'   (UTC+12, no daylight saving) which keeps a gap-free regular hourly
#'   series. Use `"Pacific/Auckland"` for civil NZ time (a duplicated hour
#'   every April, a missing hour every September).
#' @param format  `"AEME"` (default, `MET_*` names), `"LER"` (LakeEnsemblR
#'   names) or `"raw"` (ERA5 short names).
#' @param precip_units `"mm/hr"` (default), `"m/day"`, `"mm/day"` or
#'   `"m/hr"` - applied to precipitation and snowfall.
#' @param pressure_units `"Pa"` (default) or `"hPa"`.
#' @param outfile optional path; if given the frame is written there with
#'   `utils::write.csv(..., row.names = FALSE)`, time formatted
#'   `"%Y-%m-%d %H:%M:%S"`.
#' @param fill_gaps reindex onto a complete regular hourly sequence
#'   (missing steps become `NA`). Default `TRUE`.
#' @param verbose print progress messages.
#'
#' @return a data frame: a time column (`Date` for AEME, else `datetime`;
#'   POSIXct in `tz`) plus one column per variable in the chosen naming
#'   `format`. Derived `*_wndspd`, `*_wnddir` and `*_humrel` columns are
#'   added when their inputs are present. Attributes `lon`, `lat`,
#'   `method`, `tz`, `n_cells` describe the extraction.
#'
#' @examples
#' \dontrun{
#' ## by coordinate
#' met <- extract_era5_hourly_met(
#'   path = "download_era5-land/era5_netcdf",
#'   lon  = 176.2717, lat = -38.0790, years = 2023:2024)
#'
#' ## by lake polygon, area-weighted over every overlapping grid cell
#' lakes <- readRDS("gis/lake_shapefile/lernzmp_lakes_master.rds")$updated
#' poly  <- lakes[lakes$name_final == "Rotorua", ]
#' met   <- extract_era5_hourly_met(
#'   path = "download_era5-land/era5_netcdf", geom = poly,
#'   method = "area", years = 2023:2024,
#'   outfile = "rotorua_era5_hourly_met.csv")
#' }
#' @export
extract_era5_hourly_met <- function(path,
                                    lon = NULL,
                                    lat = NULL,
                                    geom = NULL,
                                    years = NULL,
                                    months = 1:12,
                                    variables = c("2m_temperature",
                                                  "2m_dewpoint_temperature",
                                                  "10m_u_component_of_wind",
                                                  "10m_v_component_of_wind",
                                                  "surface_solar_radiation_downwards",
                                                  "surface_thermal_radiation_downwards",
                                                  "total_precipitation",
                                                  "snowfall",
                                                  "surface_pressure"),
                                    method = c("bilinear", "nearest",
                                               "area", "area_mean"),
                                    tz = "Etc/GMT-12",
                                    format = c("AEME", "LER", "raw"),
                                    precip_units = c("mm/hr", "m/day",
                                                     "mm/day", "m/hr"),
                                    pressure_units = c("Pa", "hPa"),
                                    file_template = "nz_era5-land_%d_%02d_%s_daily.nc",
                                    area_crs = 2193,
                                    outfile = NULL,
                                    fill_gaps = TRUE,
                                    verbose = TRUE) {

  method         <- match.arg(method)
  format         <- match.arg(format)
  precip_units   <- match.arg(precip_units)
  pressure_units <- match.arg(pressure_units)
  stopifnot(dir.exists(path))
  if (!requireNamespace("ncdf4", quietly = TRUE))
    stop("Package 'ncdf4' is required.")

  say <- function(...) if (isTRUE(verbose)) message(...)

  ## ---- resolve location to WGS84 point + optional polygon --------------
  poly_ll <- NULL
  if (!is.null(geom)) {
    if (!requireNamespace("sf", quietly = TRUE))
      stop("Package 'sf' is required when 'geom' is supplied.")
    g <- sf::st_geometry(sf::st_as_sf(geom))
    if (is.na(sf::st_crs(g))) stop("'geom' has no CRS.")
    if (length(g) > 1) g <- sf::st_union(g)
    gtype <- as.character(sf::st_geometry_type(g, by_geometry = FALSE))
    ## centroid in the geometry's own (projected) CRS, then to lon/lat
    ctr <- sf::st_coordinates(sf::st_transform(sf::st_centroid(g), 4326))
    lon <- ctr[1, 1]; lat <- ctr[1, 2]
    if (grepl("POLYGON", gtype)) poly_ll <- sf::st_transform(g, 4326)
  }
  if (is.null(lon) || is.null(lat))
    stop("Supply either 'lon'/'lat' or 'geom'.")
  if (method %in% c("area", "area_mean") && is.null(poly_ll)) {
    say("method '", method, "' needs a polygon - falling back to 'bilinear'")
    method <- "bilinear"
  }

  ## ---- variable lookup (ERA5 name -> nc names / role / target names) --
  ref <- list(
    "2m_temperature"          = list(nc = c("t2m", "2t"),  role = "temp_k",
                                     aeme = "MET_tmpair",
                                     ler  = "Air_Temperature_celsius"),
    "2m_dewpoint_temperature" = list(nc = c("d2m", "2d"),  role = "temp_k",
                                     aeme = "MET_tmpdew",
                                     ler  = "Dewpoint_Temperature_celsius"),
    "10m_u_component_of_wind" = list(nc = c("u10", "10u"), role = "linear",
                                     aeme = "MET_wnduvu",
                                     ler  = "Ten_Meter_Uwind_vector_meterPerSecond"),
    "10m_v_component_of_wind" = list(nc = c("v10", "10v"), role = "linear",
                                     aeme = "MET_wnduvv",
                                     ler  = "Ten_Meter_Vwind_vector_meterPerSecond"),
    "surface_solar_radiation_downwards"   = list(nc = "ssrd", role = "accum_flux",
                                     aeme = "MET_radswd",
                                     ler  = "Shortwave_Radiation_Downwelling_wattPerMeterSquared"),
    "surface_thermal_radiation_downwards" = list(nc = "strd", role = "accum_flux",
                                     aeme = "MET_radlwd",
                                     ler  = "Longwave_Radiation_Downwelling_wattPerMeterSquared"),
    "total_precipitation"     = list(nc = "tp", role = "accum_depth",
                                     aeme = "MET_pprain",
                                     ler  = "Precipitation_millimeterPerHour"),
    "snowfall"                = list(nc = "sf", role = "accum_depth",
                                     aeme = "MET_ppsnow",
                                     ler  = "Snowfall_millimeterPerHour"),
    "surface_pressure"        = list(nc = "sp", role = "pressure",
                                     aeme = "MET_prsttn",
                                     ler  = "Surface_Level_Barometric_Pressure_pascal")
  )
  unknown <- setdiff(variables, names(ref))
  if (length(unknown))
    stop("Unsupported variable(s): ", paste(unknown, collapse = ", "))

  fname <- function(v, y, m)
    file.path(path, sprintf(file_template, y, m, v))

  ## ---- discover years on disk ----------------------------------------------
  ## Derive a search regex from file_template by substituting a year/month
  ## capture group and the variable name, so a custom template still works.
  if (is.null(years)) {
    all_nc <- list.files(path, pattern = "\\.nc$")
    yrs <- lapply(variables, function(v) {
      re <- gsub("%02d", "(\\\\d{2})",
                 gsub("%d", "(\\\\d{4})",
                      gsub("%s", gsub("([.\\\\+*?\\[^\\]$(){}|])", "\\\\\\1", v),
                           file_template)))
      hit <- grep(paste0("^", re, "$"), all_nc, value = TRUE)
      as.integer(sub(paste0("^", re, "$"), "\\1", hit))
    })
    years <- sort(unique(Reduce(union, yrs)))
    years <- years[!is.na(years)]
    if (!length(years))
      stop("No files matching '", file_template, "' found in ", path)
    say("Years found on disk: ", paste(range(years), collapse = "-"))
  }

  ## ---- build (ix, iy, weight) for a grid, given the chosen method -----
  ## `valid` is an optional [nlon, nlat] logical mask of cells that carry
  ## data (ERA5-Land masks the sea and, often, lake pixels themselves).
  make_weights <- function(lonv, latv, valid = NULL) {
    dlon <- stats::median(diff(sort(lonv)))
    dlat <- stats::median(abs(diff(sort(latv))))
    ok <- function(ix, iy) if (is.null(valid)) TRUE else isTRUE(valid[ix, iy])

    ## nearest valid grid node to (lon, lat)
    nearest_valid <- function() {
      gi <- expand.grid(ix = seq_along(lonv), iy = seq_along(latv))
      if (!is.null(valid)) gi <- gi[valid[cbind(gi$ix, gi$iy)] %in% TRUE, ]
      if (!nrow(gi)) stop("No valid ERA5 land cells near this location.")
      d2 <- (lonv[gi$ix] - lon)^2 + (latv[gi$iy] - lat)^2
      k  <- which.min(d2)
      data.frame(ix = gi$ix[k], iy = gi$iy[k], w = 1)
    }

    if (method == "nearest") return(nearest_valid())

    if (method == "bilinear") {
      ox <- order(lonv); oy <- order(latv)
      lons <- lonv[ox]; lats <- latv[oy]
      i <- findInterval(lon, lons, all.inside = TRUE)
      j <- findInterval(lat, lats, all.inside = TRUE)
      tx <- (lon - lons[i]) / (lons[i + 1] - lons[i])
      ty <- (lat - lats[j]) / (lats[j + 1] - lats[j])
      W <- data.frame(
        ix = c(ox[i], ox[i + 1], ox[i], ox[i + 1]),
        iy = c(oy[j], oy[j], oy[j + 1], oy[j + 1]),
        w  = c((1 - tx) * (1 - ty), tx * (1 - ty),
               (1 - tx) * ty,       tx * ty))
      keep <- mapply(ok, W$ix, W$iy)
      if (!any(keep)) return(nearest_valid())          # all corners masked
      W <- W[keep, ]; W$w <- W$w / sum(W$w)            # renormalise
      return(W)
    }

    ## ---- area / area_mean : intersect grid cells with the polygon ----
    bb  <- sf::st_bbox(poly_ll)
    inx <- which(lonv >= bb["xmin"] - dlon & lonv <= bb["xmax"] + dlon)
    iny <- which(latv >= bb["ymin"] - dlat & latv <= bb["ymax"] + dlat)
    grd <- expand.grid(ix = inx, iy = iny)
    cells <- lapply(seq_len(nrow(grd)), function(k) {
      cx <- lonv[grd$ix[k]]; cy <- latv[grd$iy[k]]
      sf::st_polygon(list(rbind(
        c(cx - dlon / 2, cy - dlat / 2), c(cx + dlon / 2, cy - dlat / 2),
        c(cx + dlon / 2, cy + dlat / 2), c(cx - dlon / 2, cy + dlat / 2),
        c(cx - dlon / 2, cy - dlat / 2))))
    })
    cells_nztm <- sf::st_transform(sf::st_sfc(cells, crs = 4326), area_crs)
    poly_nztm  <- sf::st_union(sf::st_transform(poly_ll, area_crs))
    hit <- which(lengths(sf::st_intersects(cells_nztm, poly_nztm)) > 0)
    a <- vapply(hit, function(k) {
      gi <- suppressWarnings(sf::st_intersection(cells_nztm[k], poly_nztm))
      if (length(gi) == 0) 0 else as.numeric(sum(sf::st_area(gi)))
    }, numeric(1))
    hit <- hit[a > 0]; a <- a[a > 0]
    keep <- mapply(ok, grd$ix[hit], grd$iy[hit])       # drop masked cells
    hit <- hit[keep]; a <- a[keep]
    if (!length(hit)) {                                # nothing usable
      say("  polygon overlaps no valid ERA5 cell - using nearest valid node")
      return(nearest_valid())
    }
    w <- if (method == "area_mean") rep(1 / length(a), length(a)) else a / sum(a)
    data.frame(ix = grd$ix[hit], iy = grd$iy[hit], w = w)
  }

  ## ---- read one file, collapse to the weighted point series ----------
  read_file <- function(file, nc_candidates, W) {
    nc <- ncdf4::nc_open(file); on.exit(ncdf4::nc_close(nc), add = TRUE)
    vn <- intersect(nc_candidates, names(nc$var))
    if (!length(vn)) {
      vn <- setdiff(names(nc$var), c("crs", "number", "expver", "spatial_ref"))
      vn <- vn[vapply(vn, function(x) length(nc$var[[x]]$dim) >= 3, logical(1))]
    }
    vn <- vn[1]; if (is.na(vn)) stop("No 3-D variable in ", file)

    t_nm  <- if ("valid_time" %in% names(nc$dim)) "valid_time" else "time"
    tval  <- nc$dim[[t_nm]]$vals
    tunit <- nc$dim[[t_nm]]$units
    mult  <- if (grepl("^seconds", tunit)) 1 else
             if (grepl("^hours",   tunit)) 3600 else
             if (grepl("^days",    tunit)) 86400 else NA_real_
    origin <- as.POSIXct(trimws(sub(".*since", "", tunit)), tz = "UTC",
                         tryFormats = c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M",
                                        "%Y-%m-%d"))
    tt <- origin + tval * mult

    i0 <- min(W$ix); j0 <- min(W$iy)
    di <- max(W$ix) - i0 + 1; dj <- max(W$iy) - j0 + 1
    slab <- ncdf4::ncvar_get(nc, vn, start = c(i0, j0, 1),
                             count = c(di, dj, -1))               # [lon,lat,time]
    dim(slab) <- c(di, dj, length(tt))
    ## NA-aware weighted mean: a cell that is NA at some step drops out and
    ## the remaining weights are renormalised for that step.
    num <- numeric(length(tt)); den <- numeric(length(tt))
    for (k in seq_len(nrow(W))) {
      x  <- slab[W$ix[k] - i0 + 1, W$iy[k] - j0 + 1, ]
      ok <- !is.na(x)
      num[ok] <- num[ok] + W$w[k] * x[ok]
      den[ok] <- den[ok] + W$w[k]
    }
    val <- ifelse(den > 0, num / den, NA_real_)
    data.frame(time_utc = tt, value = as.numeric(val))
  }

  ## ---- read every requested variable -----------------------------------
  wcache <- list()
  series <- list()
  for (v in variables) {
    files <- unlist(lapply(years, function(y)
      Filter(file.exists, vapply(months, function(m) fname(v, y, m), character(1)))))
    if (!length(files)) { say("  ", v, ": no files - skipped"); next }

    ## weights from this variable's grid (cache per grid signature)
    nc1  <- ncdf4::nc_open(files[1])
    lonv <- nc1$dim[[if ("longitude" %in% names(nc1$dim)) "longitude" else "lon"]]$vals
    latv <- nc1$dim[[if ("latitude"  %in% names(nc1$dim)) "latitude"  else "lat"]]$vals
    vn1  <- intersect(ref[[v]]$nc, names(nc1$var))
    if (!length(vn1))
      vn1 <- setdiff(names(nc1$var),
                     c("crs", "number", "expver", "spatial_ref"))[1]
    vmask <- !is.na(ncdf4::ncvar_get(nc1, vn1[1], start = c(1, 1, 1),
                                     count = c(-1, -1, 1)))       # [nlon, nlat]
    ncdf4::nc_close(nc1)
    key <- paste(length(lonv), length(latv), signif(lonv[1], 8), signif(latv[1], 8))
    if (is.null(wcache[[key]]))
      wcache[[key]] <- make_weights(lonv, latv, valid = vmask)
    W <- wcache[[key]]
    say("  ", v, ": ", length(files), " file(s), ", nrow(W), " grid cell(s)")

    d <- do.call(rbind, lapply(files, read_file, nc_candidates = ref[[v]]$nc, W = W))
    d <- d[!duplicated(d$time_utc), ]
    d <- d[order(d$time_utc), ]

    role <- ref[[v]]$role
    if (role %in% c("accum_flux", "accum_depth")) {
      ## ERA5-Land accumulations run from 00:00 UTC and reset at 01:00 UTC.
      ## Recover the hourly amount as a first difference, except:
      ##  - at 01:00 UTC the stored value IS the 00->01 amount;
      ##  - the leading 00:00 UTC record is a previous-day total (drop it);
      ##  - tiny negative diffs elsewhere are float noise -> clamp to 0.
      d   <- d[order(d$time_utc), ]
      hr  <- as.integer(format(d$time_utc, "%H", tz = "UTC"))
      inc <- c(NA_real_, diff(d$value))
      inc[hr == 1] <- d$value[hr == 1]
      inc[1] <- if (length(hr) && hr[1] == 1) d$value[1] else NA_real_
      inc[!is.na(inc) & inc < 0] <- 0
      d$value <- if (role == "accum_flux") inc / 3600 else inc
    } else if (role == "temp_k") {
      if (isTRUE(stats::median(d$value, na.rm = TRUE) > 100))
        d$value <- d$value - 273.15
    }
    series[[v]] <- d
  }
  if (!length(series)) stop("Nothing could be read for the requested point/period.")

  ## ---- merge to wide UTC table -------------------------------------------
  wide <- Reduce(function(a, b) merge(a, b, by = "time_utc", all = TRUE),
                 Map(function(d, v) stats::setNames(d, c("time_utc", v)),
                     series, names(series)))
  wide <- wide[order(wide$time_utc), ]

  if (isTRUE(fill_gaps)) {
    full <- data.frame(time_utc = seq(min(wide$time_utc), max(wide$time_utc), by = "hour"))
    if (nrow(full) > nrow(wide))
      say("Filled ", nrow(full) - nrow(wide), " missing hourly step(s) with NA")
    wide <- merge(full, wide, by = "time_utc", all.x = TRUE)
  }

  ## ---- unit finishing ---------------------------------------------------
  pmul <- switch(precip_units, "m/hr" = 1, "mm/hr" = 1000, "m/day" = 24, "mm/day" = 24000)
  for (v in c("total_precipitation", "snowfall"))
    if (v %in% names(wide)) wide[[v]] <- wide[[v]] * pmul
  if ("surface_pressure" %in% names(wide) && pressure_units == "hPa")
    wide[["surface_pressure"]] <- wide[["surface_pressure"]] / 100

  ## ---- derived variables (on ERA5-named columns) ----------------------
  has <- function(...) all(c(...) %in% names(wide))
  if (has("10m_u_component_of_wind", "10m_v_component_of_wind")) {
    u <- wide[["10m_u_component_of_wind"]]; vv <- wide[["10m_v_component_of_wind"]]
    wide[["wndspd"]] <- sqrt(u^2 + vv^2)
    wide[["wnddir"]] <- (270 - atan2(vv, u) * 180 / pi) %% 360        # deg FROM
  }
  if (has("2m_temperature", "2m_dewpoint_temperature")) {
    Ta <- wide[["2m_temperature"]]; Td <- wide[["2m_dewpoint_temperature"]]
    rh <- 100 * exp(17.625 * Td / (243.04 + Td)) / exp(17.625 * Ta / (243.04 + Ta))
    wide[["humrel"]] <- pmin(pmax(rh, 0), 100)
  }

  ## ---- UTC -> NZ ------------------------------------------------------
  if (requireNamespace("lubridate", quietly = TRUE)) {
    datetime <- lubridate::with_tz(wide$time_utc, tz)
  } else {
    datetime <- as.POSIXct(format(wide$time_utc, tz = tz), tz = tz)
  }
  wide$time_utc <- NULL

  ## ---- rename to requested convention --------------------------------
  nm <- stats::setNames(rep(NA_character_, length(ref) + 3),
                        c(names(ref), "wndspd", "wnddir", "humrel"))
  if (format == "AEME") {
    nm[names(ref)] <- vapply(ref, `[[`, character(1), "aeme")
    nm[c("wndspd", "wnddir", "humrel")] <- c("MET_wndspd", "MET_wnddir", "MET_humrel")
    time_col <- "Date"
  } else if (format == "LER") {
    nm[names(ref)] <- vapply(ref, `[[`, character(1), "ler")
    nm[c("wndspd", "wnddir", "humrel")] <-
      c("Ten_Meter_Wind_Speed_meterPerSecond", "Wind_Direction_degree",
        "Relative_Humidity_percent")
    time_col <- "datetime"
  } else {
    nm[names(ref)] <- vapply(ref, function(x) x$nc[1], character(1))
    nm[c("wndspd", "wnddir", "humrel")] <- c("wndspd", "wnddir", "humrel")
    time_col <- "datetime"
  }
  keep <- intersect(names(nm)[!is.na(nm)], names(wide))
  out  <- wide[, keep, drop = FALSE]
  names(out) <- nm[keep]
  out <- cbind(stats::setNames(data.frame(datetime), time_col), out)
  rownames(out) <- NULL

  ## ---- optional write ------------------------------------------------
  if (!is.null(outfile)) {
    w <- out; w[[time_col]] <- format(w[[time_col]], "%Y-%m-%d %H:%M:%S")
    utils::write.csv(w, outfile, row.names = FALSE)
    say("Wrote ", nrow(w), " rows x ", ncol(w), " cols to ", outfile)
  }

  attr(out, "lon") <- lon; attr(out, "lat") <- lat
  attr(out, "tz") <- tz;   attr(out, "method") <- method
  attr(out, "n_cells") <- nrow(wcache[[1]])
  out
}
