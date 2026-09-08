#' Preview the extraction grid, cells and geometry before extracting
#'
#' A sanity-check map drawn straight from the files that
#' [extract_era5_hourly_met()] / [extract_era5_lake_met()] would read: the
#' ERA5-Land grid around your location, the cell(s) that the chosen `method`
#' would actually sample (shaded by weight), the land/sea validity mask, and
#' your point or polygon on top. Use it to confirm the geometry lands where
#' you expect and overlaps sensible cells *before* running an extraction.
#'
#' The grid, cell selection and weights come from the same internal machinery
#' as the extractors, so what you see is what you would get. Only one file is
#' opened (the first that matches `pattern` for the first available
#' `variables` entry) - grids are identical across ERA5-Land variables and
#' months.
#'
#' On the map:
#'   * filled cells are the ones `method` samples, coloured by their weight
#'     (`"nearest"` -> one cell, weight 1; `"bilinear"` -> up to four;
#'     `"area"` / `"area_mean"` -> every cell the polygon overlaps);
#'   * grey cells are in view but not sampled;
#'   * a dashed blue outline marks cells masked out by ERA5-Land (sea, or the
#'     lake pixels themselves) - these are dropped and their weight
#'     redistributed;
#'   * grey dots are grid nodes (cell centres);
#'   * the red polygon / red cross is your `geom` (or `lon`/`lat`).
#'
#' @param path directory holding the ERA5-Land files (netCDF or GRIB), as
#'   passed to [extract_era5_hourly_met()].
#' @param lon,lat point of interest, decimal degrees (WGS84). Ignored if
#'   `geom` is supplied.
#' @param geom an `sf`/`sfc` point or polygon (any CRS); overrides
#'   `lon`/`lat`. A polygon is required for `method = "area"` /
#'   `"area_mean"`.
#' @param method spatial sampling to preview: `"bilinear"` (default),
#'   `"nearest"`, `"area"` or `"area_mean"`. See [extract_era5_hourly_met()].
#' @param variables ERA5-Land variable name(s); the first one with files on
#'   disk is used to read the grid. Default `"2m_temperature"`.
#' @param pattern file-name template, as in [extract_era5_hourly_met()].
#'   Default `"{variable}"`.
#' @param years,months optional filters passed to the file matcher (only
#'   needed when `pattern` pins `{year}` / `{month}`).
#' @param area_crs projected CRS for the `"area"` intersection, matching the
#'   extractor. Default `2193` (NZTM 2000).
#' @param max_dist_km distance cap for a `"nearest"` sample. Unlike the
#'   extractor this only warns (the plot is still drawn) so you can see how
#'   far off a mis-placed point is. Default `50`.
#' @param pad number of grid cells of context to draw around the geometry.
#'   Default `3`.
#' @param engine `"ggplot2"` (default, returns a `ggplot` you can further
#'   style or hand to `mapview`/`tmap`) or `"base"` (draws with
#'   [sf::plot()], returns the grid invisibly). `"ggplot2"` falls back to
#'   `"base"` if \pkg{ggplot2} is not installed.
#'
#' @return For `engine = "ggplot2"`, a `ggplot` object; for `"base"`, the
#'   grid `sf` (invisibly). Either way the return carries attributes
#'   `grid` (an `sf` of the drawn cells with columns `ix`, `iy`, `weight`,
#'   `selected`, `land`), `weights` (the `data.frame(ix, iy, w)` selection)
#'   and `file` (the file read).
#'
#' @seealso [extract_era5_hourly_met()], [extract_era5_lake_met()]
#'
#' @examples
#' \dontrun{
#' ## point, bilinear
#' plot_extract_grid("era5_land", lon = 176.2717, lat = -38.0790)
#'
#' ## lake polygon, area-weighted - the case worth eyeballing
#' poly <- sf::st_read("gis/rotorua.gpkg")
#' p <- plot_extract_grid("era5_land", geom = poly, method = "area")
#' p + ggplot2::coord_sf(expand = FALSE)
#'
#' ## interactive check against a basemap, no new dependency in the package
#' mapview::mapview(attr(p, "grid"), zcol = "weight")
#' }
#' @export
plot_extract_grid <- function(path,
                              lon = NULL, lat = NULL, geom = NULL,
                              method = c("bilinear", "nearest",
                                         "area", "area_mean"),
                              variables = "2m_temperature",
                              pattern = "{variable}",
                              years = NULL, months = 1:12,
                              area_crs = 2193,
                              max_dist_km = 50,
                              pad = 3,
                              engine = c("ggplot2", "base")) {

  method <- match.arg(method)
  engine <- match.arg(engine)
  if (!requireNamespace("sf", quietly = TRUE))
    stop("Package 'sf' is required for plot_extract_grid().", call. = FALSE)
  stopifnot(dir.exists(path))

  if (engine == "ggplot2" && !requireNamespace("ggplot2", quietly = TRUE)) {
    message("Package 'ggplot2' not installed - drawing with sf::plot() instead.")
    engine <- "base"
  }

  ## ---- resolve the location, mirror the extractor's area-> bilinear drop -
  loc <- .era5_resolve_location(lon, lat, geom)
  if (method %in% c("area", "area_mean") && is.null(loc$poly_ll)) {
    warning("method '", method, "' needs a polygon - previewing 'bilinear'.",
            call. = FALSE)
    method <- "bilinear"
  }

  ## ---- one file for the grid (first variable with matches) --------------
  fx <- .era5_locate_files(path, pattern, variables, years, months)
  fx <- Filter(Negate(is.null), fx)
  if (!length(fx))
    stop("No ERA5 files matching pattern '", pattern, "' found in ", path, ".",
         call. = FALSE)
  fi   <- fx[[1]]
  file <- fi$file[order(fi$year, fi$month)][1]
  gi   <- .era5_grid_info(file, .era5_ref[[names(fx)[1]]]$nc)
  lonv <- gi$lon; latv <- gi$lat; mask <- gi$mask

  ## ---- the cell selection / weights, exactly as the extractor computes --
  W <- tryCatch(
    .era5_make_weights(lonv, latv, valid = mask, method = method,
                       lon = loc$lon, lat = loc$lat, poly_ll = loc$poly_ll,
                       area_crs = area_crs, max_dist_km = max_dist_km),
    error = function(e) {
      warning(conditionMessage(e), call. = FALSE)
      .era5_make_weights(lonv, latv, valid = mask, method = method,
                         lon = loc$lon, lat = loc$lat, poly_ll = loc$poly_ll,
                         area_crs = area_crs, max_dist_km = Inf)
    })

  ## ---- window of cells to draw: context around the geometry + all picked
  d_lon <- stats::median(diff(sort(lonv)))
  d_lat <- stats::median(abs(diff(sort(latv))))
  if (!is.null(loc$poly_ll)) {
    bb <- sf::st_bbox(loc$poly_ll)
    ix_win <- which(lonv >= bb[["xmin"]] - (pad + .5) * d_lon &
                    lonv <= bb[["xmax"]] + (pad + .5) * d_lon)
    iy_win <- which(latv >= bb[["ymin"]] - (pad + .5) * d_lat &
                    latv <= bb[["ymax"]] + (pad + .5) * d_lat)
  } else {
    ix0 <- which.min(abs(lonv - loc$lon)); iy0 <- which.min(abs(latv - loc$lat))
    ix_win <- seq(ix0 - pad - 1L, ix0 + pad + 1L)
    iy_win <- seq(iy0 - pad - 1L, iy0 + pad + 1L)
  }
  ix_win <- sort(intersect(union(ix_win, min(W$ix):max(W$ix)), seq_along(lonv)))
  iy_win <- sort(intersect(union(iy_win, min(W$iy):max(W$iy)), seq_along(latv)))

  grd <- expand.grid(ix = ix_win, iy = iy_win)
  grd$lon_c  <- lonv[grd$ix]
  grd$lat_c  <- latv[grd$iy]
  grd$weight <- W$w[match(paste(grd$ix, grd$iy), paste(W$ix, W$iy))]
  grd$selected <- !is.na(grd$weight)
  grd$land   <- mask[cbind(grd$ix, grd$iy)]

  cells <- lapply(seq_len(nrow(grd)), function(k) {
    cx <- grd$lon_c[k]; cy <- grd$lat_c[k]
    sf::st_polygon(list(rbind(
      c(cx - d_lon / 2, cy - d_lat / 2), c(cx + d_lon / 2, cy - d_lat / 2),
      c(cx + d_lon / 2, cy + d_lat / 2), c(cx - d_lon / 2, cy + d_lat / 2),
      c(cx - d_lon / 2, cy - d_lat / 2))))
  })
  grid_sf  <- sf::st_sf(grd, geometry = sf::st_sfc(cells, crs = 4326))
  nodes_sf <- sf::st_as_sf(grd[c("lon_c", "lat_c", "selected")],
                           coords = c("lon_c", "lat_c"), crs = 4326)
  pt_sf    <- sf::st_sfc(sf::st_point(c(loc$lon, loc$lat)), crs = 4326)

  ## ---- caption line ----------------------------------------------------
  dist_txt <- ""
  if (method == "nearest" || nrow(W) == 1L) {
    coslat <- cos(loc$lat * pi / 180)
    dkm <- 111.195 * sqrt((latv[W$iy[1]] - loc$lat)^2 +
                          ((lonv[W$ix[1]] - loc$lon) * coslat)^2)
    dist_txt <- sprintf("  |  %.1f km point -> cell centre", dkm)
  }
  sub <- sprintf("method = %s  |  %d cell(s), sum of weights = %.2f%s",
                 method, nrow(W), sum(W$w), dist_txt)
  is_poly <- !is.null(loc$poly_ll)

  if (engine == "base") {
    rng <- range(grid_sf$weight, na.rm = TRUE)
    pal <- grDevices::hcl.colors(64, "viridis")
    col <- rep("grey94", nrow(grid_sf))
    sel <- grid_sf$selected
    col[sel] <- pal[pmax(1L, ceiling(
      (grid_sf$weight[sel] - rng[1]) / max(diff(rng), 1e-9) * 63 + 1))]
    op <- graphics::par(mar = c(3, 3, 4, 1)); on.exit(graphics::par(op))
    plot(sf::st_geometry(grid_sf), col = col, border = "grey75",
         main = paste0("ERA5 grid vs. ", if (is_poly) "polygon" else "point",
                       "\n", sub))
    plot(sf::st_geometry(grid_sf)[!grid_sf$land %in% TRUE], add = TRUE,
         border = "#3B6EA5", lty = 2, lwd = 1.5)
    plot(sf::st_geometry(nodes_sf), add = TRUE, pch = 20, cex = .5,
         col = "grey55")
    if (is_poly)
      plot(sf::st_geometry(loc$poly_ll), add = TRUE, border = "#D6201F",
           lwd = 2)
    plot(pt_sf, add = TRUE, pch = 4, cex = 1.6, lwd = 2, col = "#D6201F")
    out <- grid_sf
    attr(out, "weights") <- W; attr(out, "file") <- file
    attr(out, "grid") <- grid_sf
    return(invisible(out))
  }

  ## ---- ggplot2 -------------------------------------------------------
  masked_sf <- grid_sf[!grid_sf$land %in% TRUE, ]
  p <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = grid_sf, ggplot2::aes(fill = weight),
                     colour = "grey75", linewidth = 0.25) +
    ggplot2::scale_fill_viridis_c(option = "C", na.value = "grey94",
                                  name = "weight", limits = c(0, NA)) +
    ggplot2::geom_sf(data = nodes_sf, size = 0.5, colour = "grey55") +
    ggplot2::labs(
      title    = paste0("ERA5 grid vs. ", if (is_poly) "polygon" else "point"),
      subtitle = sub, caption = basename(file), x = NULL, y = NULL) +
    ggplot2::theme_minimal()
  if (nrow(masked_sf))
    p <- p + ggplot2::geom_sf(data = masked_sf, fill = NA, colour = "#3B6EA5",
                              linetype = "22", linewidth = 0.4)
  if (is_poly)
    p <- p + ggplot2::geom_sf(data = loc$poly_ll, fill = NA,
                              colour = "#D6201F", linewidth = 0.8)
  p <- p + ggplot2::geom_sf(data = pt_sf, shape = 4, size = 3, stroke = 1.1,
                            colour = "#D6201F")

  attr(p, "grid") <- grid_sf
  attr(p, "weights") <- W
  attr(p, "file") <- file
  p
}
