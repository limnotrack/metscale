#' Read a point from an ERA5 GRIB file
#'
#' Extract a time series at a point (or the weighted mean over a polygon) from
#' one or more GRIB files downloaded with [download_era5_cds()].
#'
#' Requires the suggested package \pkg{terra} (and \pkg{sf} when `shape` is
#' supplied).
#'
#' @param file character; path to the GRIB file. Can be a vector of paths.
#' @param shape sf object; polygon over which to take a weighted mean. If
#' `NULL` (default) the value is extracted at `lon`/`lat`.
#' @param lat numeric; latitude.
#' @param lon numeric; longitude.
#' @param method character; interpolation method passed to
#' [terra::extract()] for point extraction. Default "bilinear".
#'
#' @return A data frame with columns `DateTime`, `value`, `units`, `variable`
#' and `short_name`, sorted by `DateTime`.
#'
#' @seealso [download_era5_cds()]
#'
#' @examples
#' \dontrun{
#' lat <- -38.07782
#' lon <- 176.2673
#' files <- download_era5_cds(lat = lat, lon = lon, year = 2024, month = 1:2,
#'                            variable = "2m_temperature", path = "data/test",
#'                            user = "person@email.com")
#' df <- read_era5_grib_point(file = files, lat = lat, lon = lon)
#' }
#' @export
read_era5_grib_point <- function(file, shape = NULL, lat, lon,
                                 method = "bilinear") {

  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is required for read_era5_grib_point(). ",
         "Install it with install.packages('terra').", call. = FALSE)
  }
  if (!is.null(shape) && !requireNamespace("sf", quietly = TRUE)) {
    stop("Package 'sf' is required when 'shape' is supplied. ",
         "Install it with install.packages('sf').", call. = FALSE)
  }

  out <- lapply(file, \(f) {

    if (!file.exists(f)) {
      stop("Missing the file: ", f)
    }

    # Read the file
    r <- terra::rast(f)

    # Extract point data
    if (!is.null(shape)) {
      shape_vec <- terra::vect(shape)
      shape_vec <- terra::project(shape_vec, r)
      v <- terra::extract(r, shape_vec, fun = mean, ID = FALSE,
                          weights = TRUE) |>
        as.numeric()
    } else {
      v <- terra::extract(r, cbind(lon, lat), method = method) |>
        as.numeric()
    }

    if (all(is.na(v))) {
      warning("No data found for the point for ", f, ". Returning NA.")
    }

    # Extract units
    units <- terra::units(r) |>
      unique()

    # Extract variable name
    var_name <- terra::names(r) |>
      unique()

    # Extract variable short name
    metadata <- terra::describe(f)
    grib_element <- metadata[which(grepl("GRIB_ELEMENT", metadata))[1]]
    short_name <- trimws(gsub("GRIB_ELEMENT=", "", grib_element))

    # Extract timestamp data
    time <- terra::time(r)
    df <- data.frame(DateTime = time,
                     value = v, units = units, variable = var_name,
                     short_name = short_name)

    return(df)
  })

  dat <- out |>
    dplyr::bind_rows() |>
    dplyr::arrange(DateTime)
  return(dat)
}
