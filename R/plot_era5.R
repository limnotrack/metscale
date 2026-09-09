#' Quick-look plot of an ERA5 / ERA5-Land GRIB or netCDF file
#'
#' A fast visual check of a downloaded reanalysis file, drawn straight from
#' whatever is on disk. For every variable found in the file(s) it draws a
#' map of the field aggregated over time next to a time series - the spatial
#' mean over the whole grid, or a bilinear sample at `point`. Use it to
#' eyeball the footprint, the value range and the temporal coverage before
#' handing the file to [extract_era5_hourly_met()] /
#' [extract_era5_lake_met()].
#'
#' The reader backend is chosen from the file extension, matching the
#' extractors: `.grib` / `.grb` / `.grib2` and everything else are all read
#' with \pkg{terra}. GRIB bands are grouped into variables by their
#' `GRIB_ELEMENT` metadata; netCDF files by sub-dataset / variable name.
#' Note that \pkg{terra} sometimes mislabels ERA5 GRIB units (e.g. reporting
#' `K` values under a `C` tag); the numbers are drawn as stored.
#'
#' @param file path to an ERA5 / ERA5-Land file (netCDF or GRIB). A vector of
#'   paths is allowed and is stacked in time, per variable.
#' @param var optional character vector selecting which variable(s) to draw,
#'   matched case-insensitively against the ERA5 short name / GRIB element
#'   (e.g. `"t2m"`, `"2T"`, `"tp"`). `NULL` (default) draws every variable in
#'   the file, capped at `max_vars`.
#' @param time which slice to map. `NULL` (default) aggregates every step
#'   with `fun`; otherwise a single step given as a `POSIXct` / `Date`, a
#'   `"YYYY-MM-DD HH:MM"` string (nearest step is used), or an integer layer
#'   index (negative counts from the end).
#' @param fun aggregation for the map when `time = NULL`: one of `"mean"`
#'   (default), `"sum"`, `"min"`, `"max"`, `"sd"`, `"median"`.
#' @param point optional `c(lon, lat)` in decimal degrees (WGS84). When
#'   given, the time-series panel is a bilinear sample at that point and the
#'   point is marked on the map; otherwise the series is the grid mean.
#' @param engine `"base"` (default) draws with [terra::plot()] and base
#'   graphics and returns the summary invisibly; `"ggplot2"` returns a
#'   faceted `ggplot` of the map(s) (single variable - it takes the first
#'   when several are present) and falls back to `"base"` when \pkg{ggplot2}
#'   is not installed.
#' @param col a vector of colours for the map, or the name of an
#'   [grDevices::hcl.colors()] palette. Default `"viridis"`.
#' @param max_vars maximum number of variables to draw (default `6`).
#' @param verbose print a one-line summary per variable.
#'
#' @return For `engine = "base"`, invisibly a data frame with one row per
#'   drawn variable: `variable`, `label`, `units`, `n_layers`, `t_start`,
#'   `t_end`, `xmin` / `xmax` / `ymin` / `ymax`, `res_x` / `res_y` and
#'   `min` / `mean` / `max` of the mapped field. The per-variable time series
#'   are attached as `attr(., "series")` (a named list of
#'   `data.frame(time, value)`) and the aggregated maps as `attr(., "maps")`
#'   (a named list of `SpatRaster`). For `engine = "ggplot2"`, the `ggplot`
#'   object carrying the same attributes.
#'
#' @seealso [extract_era5_hourly_met()], [plot_extract_grid()],
#'   [read_era5_grib_point()]
#'
#' @examples
#' \dontrun{
#' f <- system.file(
#'   "extdata/era5/reanalysis-era5-land_2m_temperature_hourly_2024_1_toba.grib",
#'   package = "metscale")
#'
#' plot_era5(f)                            # map of the monthly mean + grid-mean series
#' plot_era5(f, point = c(98.6, 2.6))      # series sampled at a point
#' plot_era5(f, time = "2024-01-15 12:00") # one hour, mapped
#'
#' ## a directory of monthly files for one variable, stacked
#' plot_era5(list.files("era5_land", "2m_temperature.*\\.grib$", full.names = TRUE))
#' }
#' @export
plot_era5 <- function(file,
                      var = NULL,
                      time = NULL,
                      fun = c("mean", "sum", "min", "max", "sd", "median"),
                      point = NULL,
                      engine = c("base", "ggplot2"),
                      col = "viridis",
                      max_vars = 6L,
                      verbose = TRUE) {

  fun    <- match.arg(fun)
  engine <- match.arg(engine)

  if (!requireNamespace("terra", quietly = TRUE))
    stop("Package 'terra' is required for plot_era5(). ",
         "Install it with install.packages('terra').", call. = FALSE)
  miss <- file[!file.exists(file)]
  if (!length(file) || length(miss))
    stop("File(s) not found: ", paste(miss, collapse = ", "), call. = FALSE)
  if (!is.null(point) && (length(point) != 2L || !is.numeric(point) ||
                          anyNA(point)))
    stop("'point' must be a numeric c(lon, lat).", call. = FALSE)
  if (engine == "ggplot2" && !requireNamespace("ggplot2", quietly = TRUE)) {
    message("Package 'ggplot2' not installed - drawing with base graphics.")
    engine <- "base"
  }

  say <- function(...) if (isTRUE(verbose)) message(...)

  ## ---- gather layers, grouped into variables, stacked across files -------
  per_file <- lapply(file, .era5_file_vars)
  vnames   <- unique(unlist(lapply(per_file, names)))
  groups <- stats::setNames(lapply(vnames, function(v) {
    parts <- lapply(per_file, function(x) x[[v]])
    parts <- parts[!vapply(parts, is.null, logical(1))]
    r <- if (length(parts) == 1L) parts[[1]]$r
         else do.call(c, lapply(parts, `[[`, "r"))
    tt <- terra::time(r)
    if (!anyNA(tt)) r <- terra::subset(r, order(tt))
    list(r = r, label = parts[[1]]$label, units = parts[[1]]$units)
  }), vnames)

  if (!is.null(var)) {
    keep <- tolower(names(groups)) %in% tolower(var)
    if (!any(keep))
      stop("None of var = ", paste(var, collapse = ", "), " found. File has: ",
           paste(names(groups), collapse = ", "), call. = FALSE)
    groups <- groups[keep]
  }
  if (length(groups) > max_vars) {
    say("File has ", length(groups), " variables; drawing the first ", max_vars,
        " (raise 'max_vars' for the rest).")
    groups <- groups[seq_len(max_vars)]
  }

  ## ---- reduce each variable to (map raster, series data.frame, summary) --
  pal <- if (length(col) > 1L) col else grDevices::hcl.colors(128, col)
  one <- lapply(names(groups), function(nm) {
    g  <- groups[[nm]]
    r  <- g$r
    tt <- terra::time(r)

    if (is.null(time)) {
      m   <- terra::app(r, fun = fun, na.rm = TRUE)
      ttl <- sprintf("%s  (%s of %d steps)", g$label, fun, terra::nlyr(r))
    } else {
      li <- .era5_layer_index(time, tt, terra::nlyr(r))
      m  <- r[[li]]
      ttl <- sprintf("%s  (%s)", g$label,
                     if (!anyNA(tt)) format(tt[li], "%Y-%m-%d %H:%M %Z")
                     else paste("layer", li))
    }
    names(m) <- nm

    if (is.null(point)) {
      v <- terra::global(r, "mean", na.rm = TRUE)[, 1]
      slab <- "grid mean"
    } else {
      v <- as.numeric(terra::extract(r, cbind(point[1], point[2]),
                                     method = "bilinear")[1, ])
      slab <- sprintf("point (%.3f, %.3f)", point[1], point[2])
    }
    ser <- data.frame(time = tt, value = as.numeric(v))
    if (anyNA(tt)) ser$time <- seq_len(nrow(ser))   # no stamps: index instead

    ex <- as.vector(terra::ext(r)); rs <- terra::res(r)
    mm <- terra::global(m, c("min", "mean", "max"), na.rm = TRUE)
    summ <- data.frame(
      variable = nm, label = g$label, units = g$units %||% NA_character_,
      n_layers = terra::nlyr(r),
      t_start  = if (!anyNA(tt)) min(tt) else as.POSIXct(NA),
      t_end    = if (!anyNA(tt)) max(tt) else as.POSIXct(NA),
      xmin = ex[1], xmax = ex[2], ymin = ex[3], ymax = ex[4],
      res_x = rs[1], res_y = rs[2],
      min = mm[[1]], mean = mm[[2]], max = mm[[3]],
      stringsAsFactors = FALSE)

    if (isTRUE(verbose))
      say(sprintf("  %-6s %s | %d steps%s | value %.3g to %.3g",
                  nm, g$label, terra::nlyr(r),
                  if (!anyNA(tt))
                    paste0(" | ", format(min(tt), "%Y-%m-%d"), " to ",
                           format(max(tt), "%Y-%m-%d")) else "",
                  summ$min, summ$max))

    list(map = m, series = ser, summ = summ, title = ttl, slab = slab)
  })
  names(one) <- names(groups)

  summary_df <- do.call(rbind, lapply(one, `[[`, "summ"))
  rownames(summary_df) <- NULL
  series_l <- lapply(one, `[[`, "series")
  maps_l   <- lapply(one, `[[`, "map")

  ## ---- ggplot2: faceted map of the first variable -----------------------
  if (engine == "ggplot2") {
    x1 <- one[[1]]
    df <- as.data.frame(x1$map, xy = TRUE)
    names(df)[3] <- "value"
    p <- ggplot2::ggplot(df, ggplot2::aes(x, y, fill = value)) +
      ggplot2::geom_raster() +
      ggplot2::scale_fill_gradientn(colours = pal,
                                    name = x1$summ$units %||% "") +
      ggplot2::coord_equal() +
      ggplot2::labs(title = x1$title, subtitle = basename(file)[1],
                    x = NULL, y = NULL) +
      ggplot2::theme_minimal()
    if (!is.null(point))
      p <- p + ggplot2::annotate("point", x = point[1], y = point[2],
                                 shape = 4, size = 3, stroke = 1.1,
                                 colour = "#D6201F")
    attr(p, "summary") <- summary_df
    attr(p, "series")  <- series_l
    attr(p, "maps")    <- maps_l
    return(p)
  }

  ## ---- base: one row per variable, map | series -------------------------
  nv <- length(one)
  op <- graphics::par(mfrow = c(nv, 2), mar = c(3.4, 3.6, 2.6, 3.4),
                      mgp = c(2, 0.6, 0))
  on.exit(graphics::par(op), add = TRUE)

  for (x in one) {
    terra::plot(x$map, main = x$title, col = pal, mar = c(3.4, 3.6, 2.6, 3.4))
    if (!is.null(point))
      graphics::points(point[1], point[2], pch = 4, cex = 1.6, lwd = 2,
                       col = "#D6201F")
    s <- x$series
    if (all(is.na(s$value))) {
      graphics::plot.new()
      graphics::title(main = paste0(x$slab, " - all NA"))
    } else {
      graphics::plot(s$time, s$value, type = "l", col = "#3B6EA5",
                     xlab = if (inherits(s$time, "POSIXct")) "" else "layer",
                     ylab = x$summ$units %||% "value", main = x$slab)
      graphics::grid(col = "grey90")
    }
  }

  attr(summary_df, "series") <- series_l
  attr(summary_df, "maps")   <- maps_l
  invisible(summary_df)
}

## ---------------------------------------------------------------------------
## helpers
## ---------------------------------------------------------------------------

#' Read one ERA5 file into a named list of `list(r, label, units)`, one entry
#' per variable. GRIB bands are grouped by `GRIB_ELEMENT`; netCDF by
#' sub-dataset. `.era5_fmt()` lives in R/era5_grid.R.
#' @noRd
.era5_file_vars <- function(f) {
  if (.era5_fmt(f) == "grib") {
    r  <- terra::rast(f)
    md <- terra::describe(f)
    grab <- function(tag) {
      hit <- grep(paste0(tag, "="), md, value = TRUE)
      if (!length(hit)) return(character(0))
      trimws(sub(paste0(".*", tag, "="), "", hit))
    }
    el <- grab("GRIB_ELEMENT"); cm <- grab("GRIB_COMMENT"); un <- grab("GRIB_UNIT")
    un <- gsub("^\\[|\\]$", "", un)
    if (length(el) != terra::nlyr(r))
      el <- rep(tools::file_path_sans_ext(basename(f)), terra::nlyr(r))
    idx <- split(seq_len(terra::nlyr(r)), factor(el, levels = unique(el)))
    out <- lapply(names(idx), function(k) {
      i <- idx[[k]]
      list(r = terra::subset(r, i),
           label = if (length(cm) >= i[1]) cm[i[1]] else k,
           units = if (length(un) >= i[1]) un[i[1]] else terra::units(r)[i[1]])
    })
    return(stats::setNames(out, tolower(names(idx))))
  }

  ## netCDF and anything else terra can open
  drop <- c("crs", "spatial_ref", "spatial ref", "number", "expver")
  d <- tryCatch(terra::sds(f), error = function(e) NULL)
  if (!is.null(d) && length(d) >= 1L) {
    nms <- names(d)
    out <- list()
    for (i in seq_len(length(d))) {
      if (tolower(nms[i]) %in% drop) next
      ri <- tryCatch(d[i], error = function(e) NULL)
      if (is.null(ri) || terra::nlyr(ri) < 1L) next
      ln <- terra::longnames(ri)[1]
      out[[nms[i]]] <- list(
        r = ri, units = terra::units(ri)[1],
        label = if (!is.na(ln) && nzchar(ln)) ln else nms[i])
    }
    if (length(out)) return(out)
  }

  r  <- terra::rast(f)
  vn <- unique(terra::varnames(r)); vn <- vn[nzchar(vn)]
  vn <- if (length(vn)) vn[1] else "value"
  stats::setNames(list(list(r = r, units = terra::units(r)[1], label = vn)), vn)
}

#' Resolve a `time` argument to a 1-based layer index into `tt`
#' (the layer time stamps; may be all `NA`). Integer indices pass through
#' (negatives count from the end); anything else is coerced to `POSIXct`
#' and matched to the nearest stamp.
#' @noRd
.era5_layer_index <- function(time, tt, n) {
  if (is.numeric(time)) {
    i <- as.integer(time)[1]
    if (i < 0L) i <- n + i + 1L
    if (i < 1L || i > n)
      stop("'time' index ", time, " is outside 1:", n, ".", call. = FALSE)
    return(i)
  }
  target <- tryCatch(as.POSIXct(time, tz = "UTC"), error = function(e) NA)
  if (is.na(target))
    stop("Could not read 'time' - give a POSIXct/Date, a ",
         "\"YYYY-MM-DD HH:MM\" string, or an integer layer index.",
         call. = FALSE)
  if (anyNA(tt))
    stop("This file has no per-layer time stamps; select 'time' by integer ",
         "index instead.", call. = FALSE)
  which.min(abs(as.numeric(tt) - as.numeric(target)))
}
