#' Hourly ERA5-Land meteorology for one named lake
#'
#' Convenience wrapper around [extract_era5_hourly_met()] that looks a lake
#' up in a polygon layer by id or name and forwards its geometry.
#'
#' The lookup is aimed at the LERNZmp `lernzmp_lakes_master` layer (a list
#' with `original` / `updated` `sf` layers in NZGD2000 / NZTM, EPSG:2193)
#' but works with any `sf` layer carrying one or more of the identifier
#' columns listed under `lake`.
#'
#' @param lake  a lake identifier matched against `id_final` (e.g.
#'   `"LID 1"` or `"1"`), `id_LID`, `name_final`, `name_fenz`,
#'   `name_english` or `name_maori` (case-insensitive); or an `sf`/`sfc`
#'   polygon to use directly, in which case `lakes` is not needed.
#' @param path  directory with the ERA5-Land netCDF files.
#' @param lakes an `sf` polygon layer, a named list of such layers (see
#'   `layer`), or a path to an `.rds` holding either. Required unless
#'   `lake` is itself a geometry.
#' @param layer when `lakes` is a list of layers, which element to use.
#'   Default `"updated"`, falling back to the only/first element.
#' @param method spatial sampling passed to [extract_era5_hourly_met()]:
#'   `"area"` (area-weighted mean of every overlapping ERA5 cell - best
#'   when a lake straddles several cells), `"area_mean"` (unweighted mean
#'   of overlapping cells), `"bilinear"` (4 nodes around the lake
#'   centroid, the default) or `"nearest"`.
#' @param ...   further arguments for [extract_era5_hourly_met()]
#'   (`years`, `months`, `variables`, `tz`, `format`, `precip_units`,
#'   `pressure_units`, `outfile`, `fill_gaps`, `verbose`).
#'
#' @return the data frame from [extract_era5_hourly_met()], with extra
#'   attributes `lake_id` and `lake_name`.
#'
#' @examples
#' \dontrun{
#' lakes <- readRDS("gis/lake_shapefile/lernzmp_lakes_master.rds")
#'
#' met <- extract_era5_lake_met(
#'   lake   = "Rotorua",
#'   path   = "download_era5-land/era5_netcdf",
#'   lakes  = lakes,
#'   method = "area",
#'   years  = 2023:2024,
#'   outfile = "rotorua_era5_hourly_met.csv")
#'
#' ## loop over a set of lakes
#' ids <- c("LID 25994", "LID 25998", "LID 54732")
#' mets <- lapply(ids, extract_era5_lake_met,
#'                path = "download_era5-land/era5_netcdf",
#'                lakes = lakes, method = "area", years = 2024)
#' }
#' @export
extract_era5_lake_met <- function(lake,
                                  path,
                                  lakes = NULL,
                                  layer = "updated",
                                  method = c("area", "area_mean",
                                             "bilinear", "nearest"),
                                  ...) {

  method <- match.arg(method)
  if (!requireNamespace("sf", quietly = TRUE))
    stop("Package 'sf' is required.")

  ## ---- obtain the lakes sf layer -------------------------------------
  if (inherits(lake, c("sf", "sfc"))) {
    poly <- sf::st_geometry(sf::st_as_sf(lake))
    lid <- NA_character_; lname <- NA_character_
  } else {
    if (is.null(lakes))
      stop("'lakes' is required when 'lake' is an id or name: supply an sf ",
           "polygon layer, a named list of layers, or a path to an .rds.")
    if (is.character(lakes) && length(lakes) == 1L && file.exists(lakes))
      lakes <- readRDS(lakes)
    if (is.list(lakes) && !inherits(lakes, "sf")) {
      if (!layer %in% names(lakes)) {
        if (length(lakes) == 1L) {
          layer <- names(lakes)[1]
        } else {
          stop("Layer '", layer, "' not in the lakes list (have: ",
               paste(names(lakes), collapse = ", "), ")")
        }
      }
      lk <- lakes[[layer]]
    } else {
      lk <- lakes
    }
    if (!inherits(lk, "sf")) stop("Could not resolve a lakes 'sf' layer.")

    ## ---- match the requested lake ----------------------------------
    key <- trimws(as.character(lake))
    cols <- intersect(c("id_final", "id_LID", "name_final", "name_fenz",
                        "name_english", "name_maori"), names(lk))
    hit <- rep(FALSE, nrow(lk))
    for (cc in cols) {
      vals <- as.character(lk[[cc]])
      hit <- hit | (!is.na(vals) &
                      (tolower(vals) == tolower(key) |
                       tolower(vals) == tolower(paste("LID", key)) |
                       tolower(sub("^LID\\s*", "", vals)) == tolower(key)))
    }
    if (!any(hit)) {                                    # loose contains-match
      for (cc in setdiff(cols, c("id_final", "id_LID"))) {
        vals <- as.character(lk[[cc]])
        hit <- hit | (!is.na(vals) & grepl(key, vals, ignore.case = TRUE))
      }
    }
    n <- sum(hit)
    if (n == 0) stop("No lake matched '", lake, "'.")
    if (n > 1) {
      nmc <- if ("name_final" %in% names(lk)) "name_final" else cols[1]
      warning(n, " lakes matched '", lake, "'; using the first: ",
              paste(utils::head(lk[[nmc]][hit], n), collapse = ", "))
    }
    row  <- which(hit)[1]
    poly <- sf::st_geometry(lk[row, ])
    lid   <- if ("id_final" %in% names(lk)) as.character(lk$id_final[row]) else NA
    lname <- if ("name_final" %in% names(lk)) as.character(lk$name_final[row]) else NA
  }

  out <- extract_era5_hourly_met(path = path, geom = poly, method = method, ...)
  attr(out, "lake_id")   <- lid
  attr(out, "lake_name") <- lname
  out
}
