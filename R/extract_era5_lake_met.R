#' Hourly ERA5-Land meteorology averaged over a lake polygon
#'
#' Thin convenience wrapper around [extract_era5_hourly_met()]: it takes a
#' single lake outline, defaults `method` to `"area"` (the area-weighted
#' mean of every overlapping ERA5 grid cell, best when a lake straddles
#' several cells) and tags the result with optional `id` / `name` labels.
#'
#' For a point, a raw geometry, or full control use
#' [extract_era5_hourly_met()] directly.
#'
#' @param polygon the lake outline: an `sf` / `sfc` polygon in any CRS, a
#'   path to a vector file [sf::st_read()] can open (`.gpkg`, `.shp`, ...),
#'   or a path to an `.rds` holding an `sf` / `sfc`. Several features are
#'   unioned into one.
#' @param path  directory holding the ERA5-Land files (netCDF or GRIB); see
#'   [extract_era5_hourly_met()] for how files are matched and the reader
#'   backend chosen.
#' @param method spatial sampling, default `"area"`. See
#'   [extract_era5_hourly_met()] for `"area"`, `"area_mean"`, `"bilinear"`
#'   and `"nearest"`.
#' @param id,name optional labels stored on the result as attributes
#'   `lake_id` / `lake_name` - handy when binding many lakes together.
#' @param ...   further arguments for [extract_era5_hourly_met()]
#'   (`years`, `months`, `variables`, `tz`, `format`, `precip_units`,
#'   `pressure_units`, `pattern`, `max_dist_km`, `outfile`, `fill_gaps`,
#'   `verbose`).
#'
#' @return the data frame from [extract_era5_hourly_met()], with extra
#'   attributes `lake_id` and `lake_name`.
#'
#' @examples
#' \dontrun{
#' poly <- sf::st_read("gis/rotorua.gpkg")
#'
#' met <- extract_era5_lake_met(
#'   poly,
#'   path    = "era5_land",
#'   years   = 2023:2024,
#'   name    = "Rotorua",
#'   outfile = "rotorua_era5_hourly_met.csv")
#'
#' ## batch over a multi-lake layer
#' lakes <- sf::st_read("gis/lakes.gpkg")
#' mets  <- lapply(seq_len(nrow(lakes)), function(i)
#'   extract_era5_lake_met(lakes[i, ], path = "era5_land", years = 2024,
#'                         id = lakes$id[i], name = lakes$name[i]))
#' }
#' @export
extract_era5_lake_met <- function(polygon,
                                  path,
                                  method = c("area", "area_mean",
                                             "bilinear", "nearest"),
                                  id = NULL,
                                  name = NULL,
                                  ...) {

  method <- match.arg(method)
  if (!requireNamespace("sf", quietly = TRUE))
    stop("Package 'sf' is required.", call. = FALSE)

  ## ---- resolve `polygon` to an sfc -----------------------------------
  if (is.character(polygon) && length(polygon) == 1L) {
    if (!file.exists(polygon))
      stop("'polygon' file not found: ", polygon, call. = FALSE)
    polygon <- if (grepl("\\.rds$", polygon, ignore.case = TRUE))
      readRDS(polygon) else sf::st_read(polygon, quiet = TRUE)
  }
  if (!inherits(polygon, c("sf", "sfc")))
    stop("'polygon' must be an sf/sfc geometry, or a path to one.",
         call. = FALSE)

  geom <- sf::st_geometry(sf::st_as_sf(polygon))
  if (length(geom) > 1L) geom <- sf::st_union(geom)
  if (is.na(sf::st_crs(geom)))
    stop("'polygon' has no CRS - set one with sf::st_crs().", call. = FALSE)

  out <- extract_era5_hourly_met(path = path, geom = geom, method = method, ...)
  attr(out, "lake_id")   <- if (is.null(id))   NA_character_ else as.character(id)
  attr(out, "lake_name") <- if (is.null(name)) NA_character_ else as.character(name)
  out
}
