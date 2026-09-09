## ---------------------------------------------------------------------------
## Shared ERA5-Land grid machinery: the variable lookup, file discovery by the
## {variable}/{year}/{month} name pattern, grid axes + validity mask, and the
## (ix, iy, weight) sampler for a point or polygon.
##
## Used by extract_era5_hourly_met() (the extraction) and plot_extract_grid()
## (the pre-extraction sanity-check plot) so the two never drift apart.
## ---------------------------------------------------------------------------

#' ERA5-Land variable lookup: ERA5 name -> nc/short names, de-accumulation
#' role and the AEME / LakeEnsemblR target names.
#' @noRd
.era5_ref <- list(
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

#' Rename an AEME-named (`MET_*`, `Date`) ERA5 frame to LakeEnsemblR or raw
#' ERA5 short names.
#'
#' Covers the nine standard variables (from `.era5_ref`), the derived
#' wind / humidity columns, the `*min` / `*max` daily temperature columns
#' and the leading time column (`Date` -> `datetime`). Columns with no
#' mapping are left untouched.
#' @noRd
.era5_rename_from_aeme <- function(df, format = c("LER", "raw")) {
  format <- match.arg(format)
  ref  <- .era5_ref
  aeme <- vapply(ref, `[[`, character(1), "aeme")
  tgt  <- if (format == "LER") vapply(ref, `[[`, character(1), "ler")
          else                 vapply(ref, function(x) x$nc[1], character(1))
  map  <- stats::setNames(tgt, aeme)

  extra <- if (format == "LER")
    c(Date       = "datetime",
      MET_wndspd = "Ten_Meter_Wind_Speed_meterPerSecond",
      MET_wnddir = "Wind_Direction_degree",
      MET_humrel = "Relative_Humidity_percent",
      MET_airmin = "Air_Temperature_min_celsius",
      MET_airmax = "Air_Temperature_max_celsius",
      MET_dewmin = "Dewpoint_Temperature_min_celsius",
      MET_dewmax = "Dewpoint_Temperature_max_celsius")
  else
    c(Date       = "datetime",
      MET_wndspd = "wndspd", MET_wnddir = "wnddir", MET_humrel = "humrel",
      MET_airmin = "t2m_min", MET_airmax = "t2m_max",
      MET_dewmin = "d2m_min", MET_dewmax = "d2m_max")
  map <- c(map, extra)

  hit <- match(names(df), names(map))
  names(df)[!is.na(hit)] <- unname(map[hit[!is.na(hit)]])
  df
}

#' Reader backend for one file, from its extension: GRIB (.grib/.grb/.grib2)
#' is read with 'terra', everything else with 'ncdf4'.
#' @noRd
.era5_fmt <- function(f) {
  ext <- tolower(tools::file_ext(f))
  if (ext %in% c("grib", "grb", "grib2", "grb2")) "grib" else "nc"
}

#' @noRd
.era5_req_pkg <- function(p)
  if (!requireNamespace(p, quietly = TRUE))
    stop("Package '", p, "' is required to read these ERA5 files.",
         call. = FALSE)

#' Locate ERA5-Land files by matching `pattern` against the names in `path`
#'
#' `pattern` carries the tokens {variable} / {year} / {month} and `*`
#' wildcards; it is turned into a regex and matched unanchored against each
#' met-extension file name. {variable} also matches the ERA5 short name(s);
#' {year} / {month} pin and enable filtering on those fields, and with no
#' {year} token the first 4-digit run in the name is taken as the year.
#'
#' @return a named list (one entry per `variables`) of `data.frame(file,
#'   year, month)`, or `NULL` where nothing matched.
#' @noRd
.era5_locate_files <- function(path, pattern, variables,
                               years = NULL, months = 1:12) {

  ref <- .era5_ref
  unknown <- setdiff(variables, names(ref))
  if (length(unknown))
    stop("Unsupported variable(s): ", paste(unknown, collapse = ", "))

  esc_rx <- function(s) gsub("([][{}().+*?^$|\\\\-])", "\\\\\\1", s)
  var_alts <- function(v) {
    sn <- ref[[v]]$nc
    sn <- ifelse(nchar(sn) <= 3L, paste0("\\b", esc_rx(sn), "\\b"), esc_rx(sn))
    paste0("(?:", paste(c(esc_rx(v), sn), collapse = "|"), ")")
  }
  pattern_rx <- function(v) {
    toks <- regmatches(pattern, gregexpr(
      "\\{variable\\}|\\{year\\}|\\{month\\}|\\*|[^{}*]+", pattern))[[1]]
    ny <- 0L; nm <- 0L
    body <- vapply(toks, function(p) switch(p,
      "{variable}" = var_alts(v),
      "{year}"  = { ny <<- ny + 1L; if (ny == 1L) "(\\d{4})"   else "\\d{4}" },
      "{month}" = { nm <<- nm + 1L; if (nm == 1L) "(\\d{1,2})" else "\\d{1,2}" },
      "*"       = ".*",
      esc_rx(p)), character(1), USE.NAMES = FALSE)
    list(rx = paste(body, collapse = ""), has_year = ny > 0L, has_month = nm > 0L)
  }

  pool <- list.files(path)
  pool <- pool[grepl("\\.(nc|grib|grib2|grb|grb2)$", pool, ignore.case = TRUE)]

  files_for <- function(v) {
    pr  <- pattern_rx(v)
    cap <- regmatches(pool, regexec(pr$rx, pool, perl = TRUE))
    hit <- lengths(cap) > 0
    if (!any(hit)) return(NULL)
    pool <- pool[hit]; cap <- cap[hit]
    if (pr$has_year) {
      yr <- vapply(cap, function(x) as.integer(x[2]), integer(1))
    } else {
      m4 <- regexpr("\\d{4}", pool)
      yr <- rep(NA_integer_, length(pool))
      yr[m4 > 0] <- as.integer(regmatches(pool, m4))
    }
    mo <- rep(NA_integer_, length(pool))
    if (pr$has_month)
      mo <- vapply(cap, function(x) as.integer(x[if (pr$has_year) 3L else 2L]),
                   integer(1))
    keep <- !is.na(yr)
    if (!is.null(years)) keep <- keep & yr %in% years
    if (pr$has_month)    keep <- keep & (is.na(mo) | mo %in% months)
    if (!any(keep)) return(NULL)
    data.frame(file = file.path(path, pool[keep]), year = yr[keep],
               month = mo[keep], stringsAsFactors = FALSE)
  }

  stats::setNames(lapply(variables, files_for), variables)
}

#' Grid axes + a validity mask (cells carrying data at step 1) for one file
#'
#' @return `list(lon, lat, mask)` with `mask` a `[nlon, nlat]` logical of
#'   cells that are not `NA` at the first time step (ERA5-Land masks the sea
#'   and often the lake pixels themselves).
#' @noRd
.era5_grid_info <- function(file, nc_candidates) {
  if (.era5_fmt(file) == "grib") {
    .era5_req_pkg("terra")
    r   <- terra::rast(file)
    lon <- as.numeric(terra::xFromCol(r, seq_len(terra::ncol(r))))
    lat <- as.numeric(terra::yFromRow(r, seq_len(terra::nrow(r))))
    m1  <- terra::as.array(r[[1]])[, , 1]                    # [lat, lon]
    return(list(lon = lon, lat = lat, mask = t(!is.na(m1)))) # [nlon, nlat]
  }
  .era5_req_pkg("ncdf4")
  nc <- ncdf4::nc_open(file); on.exit(ncdf4::nc_close(nc), add = TRUE)
  lon <- nc$dim[[if ("longitude" %in% names(nc$dim)) "longitude" else "lon"]]$vals
  lat <- nc$dim[[if ("latitude"  %in% names(nc$dim)) "latitude"  else "lat"]]$vals
  vn  <- intersect(nc_candidates, names(nc$var))
  if (!length(vn))
    vn <- setdiff(names(nc$var),
                  c("crs", "number", "expver", "spatial_ref"))[1]
  mask <- !is.na(ncdf4::ncvar_get(nc, vn[1], start = c(1, 1, 1),
                                  count = c(-1, -1, 1)))     # [nlon, nlat]
  list(lon = lon, lat = lat, mask = mask)
}

#' Build the `(ix, iy, weight)` sample for a grid, given the chosen method
#'
#' Mirrors the spatial sampling documented on [extract_era5_hourly_met()].
#' `valid` is an optional `[nlon, nlat]` logical mask of cells that carry
#' data; masked corners / cells drop out and the remaining weights are
#' renormalised, falling back to the nearest valid node when nothing is left.
#'
#' @return `data.frame(ix, iy, w)` - grid indices (1-based into `lonv` /
#'   `latv`) and weights summing to 1.
#' @noRd
.era5_make_weights <- function(lonv, latv, valid = NULL,
                               method = c("bilinear", "nearest",
                                          "area", "area_mean"),
                               lon, lat, poly_ll = NULL,
                               area_crs = 2193, max_dist_km = 50,
                               say = function(...) invisible()) {

  method <- match.arg(method)
  dlon <- stats::median(diff(sort(lonv)))
  dlat <- stats::median(abs(diff(sort(latv))))
  ok <- function(ix, iy) if (is.null(valid)) TRUE else isTRUE(valid[ix, iy])

  ## nearest valid grid node to (lon, lat), with a distance report / cap
  nearest_valid <- function() {
    gi <- expand.grid(ix = seq_along(lonv), iy = seq_along(latv))
    if (!is.null(valid)) gi <- gi[valid[cbind(gi$ix, gi$iy)] %in% TRUE, ]
    if (!nrow(gi)) stop("No valid ERA5 land cells anywhere in the grid.")
    coslat <- cos(lat * pi / 180)
    dkm <- 111.195 * sqrt((latv[gi$iy] - lat)^2 +
                          ((lonv[gi$ix] - lon) * coslat)^2)
    k <- which.min(dkm)
    say(sprintf("  nearest valid ERA5 cell is %.1f km from (%.4f, %.4f)",
                dkm[k], lon, lat))
    if (is.finite(max_dist_km) && dkm[k] > max_dist_km)
      stop(sprintf(paste0("Nearest valid ERA5 cell is %.1f km from (%.4f, ",
                          "%.4f), beyond max_dist_km = %g. Check lon/lat / ",
                          "the data region, or raise max_dist_km."),
                   dkm[k], lon, lat, max_dist_km))
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
  if (is.null(poly_ll))
    stop("method '", method, "' needs a polygon geometry.", call. = FALSE)
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

#' Resolve a location argument to a WGS84 point (+ optional WGS84 polygon)
#'
#' Accepts `lon`/`lat` scalars or an `sf`/`sfc` `geom` in any CRS. Several
#' features are unioned; the point is the polygon centroid.
#'
#' @return `list(lon, lat, poly_ll)` with `poly_ll` an `sfc` in EPSG:4326 or
#'   `NULL` for a point.
#' @noRd
.era5_resolve_location <- function(lon = NULL, lat = NULL, geom = NULL) {
  poly_ll <- NULL
  if (!is.null(geom)) {
    .era5_req_pkg("sf")
    g <- sf::st_geometry(sf::st_as_sf(geom))
    if (is.na(sf::st_crs(g))) stop("'geom' has no CRS.", call. = FALSE)
    if (length(g) > 1) g <- sf::st_union(g)
    gtype <- as.character(sf::st_geometry_type(g, by_geometry = FALSE))
    ctr <- sf::st_coordinates(sf::st_transform(sf::st_centroid(g), 4326))
    lon <- ctr[1, 1]; lat <- ctr[1, 2]
    if (grepl("POLYGON", gtype)) poly_ll <- sf::st_transform(g, 4326)
  }
  if (is.null(lon) || is.null(lat))
    stop("Supply either 'lon'/'lat' or 'geom'.", call. = FALSE)
  list(lon = lon, lat = lat, poly_ll = poly_ll)
}
