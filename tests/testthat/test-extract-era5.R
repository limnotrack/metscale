# Fixtures: write tiny hourly ERA5-Land-style files and read them back with
# extract_era5_hourly_met() / extract_era5_lake_met(), covering the netCDF
# and GRIB backends, the `pattern` file matcher and `max_dist_km`.

make_grid <- function(start = "2024-01-01 00:00", n_hours = 72) {
  list(
    lon = seq(176.0, 176.4, by = 0.1),
    lat = seq(-38.2, -37.8, by = 0.1),
    time = seq(as.POSIXct(start, tz = "UTC"), by = "hour",
               length.out = n_hours)
  )
}

# deterministic field: smooth in space, sinusoidal in time
field <- function(g, base, amp) {
  nx <- length(g$lon); ny <- length(g$lat); nt <- length(g$time)
  a <- array(0, c(nx, ny, nt))
  for (k in seq_len(nt)) {
    hr <- as.integer(format(g$time[k], "%H", tz = "UTC"))
    a[, , k] <- outer(seq_len(nx), seq_len(ny),
                      function(i, j) base + amp * sin(2 * pi * hr / 24) +
                        0.01 * i - 0.02 * j)
  }
  a
}

write_nc <- function(path, g, arr, nc_name = "t2m") {
  skip_if_not_installed("ncdf4")
  londim <- ncdf4::ncdim_def("longitude", "degrees_east", g$lon)
  latdim <- ncdf4::ncdim_def("latitude", "degrees_north", g$lat)
  tdim <- ncdf4::ncdim_def("valid_time", "seconds since 1970-01-01 00:00:00",
                           as.numeric(g$time))
  v <- ncdf4::ncvar_def(nc_name, "unit", list(londim, latdim, tdim),
                        missval = -9999)
  nc <- ncdf4::nc_create(path, list(v))
  ncdf4::ncvar_put(nc, v, arr)
  ncdf4::nc_close(nc)
  path
}

write_grib <- function(path, g, arr) {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = length(g$lat), ncols = length(g$lon),
                   xmin = min(g$lon) - 0.05, xmax = max(g$lon) + 0.05,
                   ymin = min(g$lat) - 0.05, ymax = max(g$lat) + 0.05,
                   crs = "EPSG:4326", nlyrs = length(g$time))
  for (k in seq_along(g$time))
    terra::values(r[[k]]) <- as.vector(t(arr[, rev(seq_along(g$lat)), k]))
  terra::time(r) <- g$time
  terra::writeRaster(r, path, filetype = "GRIB", overwrite = TRUE)
  path
}

# terra's GDAL GRIB writer does not preserve per-step timestamps on every
# build; the equality test needs one that does.
grib_time_roundtrips <- function(path, g)
  length(unique(terra::time(terra::rast(path)))) == length(g$time)


test_that("extract_era5_hourly_met() reads a netCDF point series", {
  skip_if_not_installed("ncdf4")
  g <- make_grid()
  dir <- tempfile("era5nc"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  met <- extract_era5_hourly_met(
    path = dir, lon = 176.2, lat = -38.0,
    variables = "2m_temperature", method = "nearest",
    tz = "UTC", fill_gaps = FALSE, verbose = FALSE)

  expect_s3_class(met, "data.frame")
  expect_true(all(c("Date", "MET_tmpair") %in% names(met)))
  expect_identical(nrow(met), length(g$time))
  expect_true(all(met$MET_tmpair > 5 & met$MET_tmpair < 30))   # K -> degC
})

test_that("the default pattern finds ad-hoc file names", {
  skip_if_not_installed("ncdf4")
  g <- make_grid()
  dir <- tempfile("era5adhoc"); dir.create(dir)
  # short name, year first, no month, unusual separators
  write_nc(file.path(dir, "ERA5land.2024.t2m.hourly.nc"), g, field(g, 288, 4))

  met <- extract_era5_hourly_met(
    path = dir, lon = 176.2, lat = -38.0, variables = "2m_temperature",
    method = "nearest", tz = "UTC", fill_gaps = FALSE, verbose = FALSE)
  expect_identical(nrow(met), length(g$time))
})

test_that("pattern tokens pin fields and enable month filtering", {
  skip_if_not_installed("ncdf4")
  dir <- tempfile("era5pat"); dir.create(dir)
  for (mm in 1:2) {
    g <- make_grid(sprintf("2024-%02d-01 00:00", mm), n_hours = 48)
    write_nc(file.path(dir, sprintf("cds_2m_temperature_hourly_2024_%d_x.nc", mm)),
             g, field(g, 288, 2))
  }

  met <- extract_era5_hourly_met(
    path = dir, lon = 176.2, lat = -38.0, variables = "2m_temperature",
    method = "nearest", months = 2,
    pattern = "{variable}_hourly_{year}_{month}_", tz = "UTC",
    fill_gaps = FALSE, verbose = FALSE)

  expect_true(nrow(met) > 0)
  expect_true(all(format(met$Date, "%m") == "02"))
})

test_that("max_dist_km caps a far-away nearest sample", {
  skip_if_not_installed("ncdf4")
  g <- make_grid()
  dir <- tempfile("era5far"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  # ~140 km east of the grid's eastern edge
  expect_error(
    extract_era5_hourly_met(path = dir, lon = 178.0, lat = -38.0,
                            variables = "2m_temperature", method = "nearest",
                            tz = "UTC", verbose = FALSE),
    "max_dist_km")

  met <- extract_era5_hourly_met(
    path = dir, lon = 178.0, lat = -38.0, variables = "2m_temperature",
    method = "nearest", max_dist_km = Inf, tz = "UTC",
    fill_gaps = FALSE, verbose = FALSE)
  expect_identical(nrow(met), length(g$time))
})

test_that("netCDF and GRIB backends agree on the extracted series", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("terra")

  g <- make_grid()
  arr <- field(g, 288, 4)
  dir_nc <- tempfile("era5nc"); dir.create(dir_nc)
  dir_gr <- tempfile("era5gr"); dir.create(dir_gr)

  write_nc(file.path(dir_nc, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, arr)
  f_gr <- write_grib(
    file.path(dir_gr, "nz_era5-land_2024_01_2m_temperature_daily.grib"), g, arr)
  skip_if_not(grib_time_roundtrips(f_gr, g),
              "terra GRIB writer does not preserve per-step timestamps here")

  common <- list(lon = 176.23, lat = -38.03, variables = "2m_temperature",
                 method = "bilinear", tz = "UTC", fill_gaps = FALSE,
                 verbose = FALSE)
  met_nc <- do.call(extract_era5_hourly_met, c(list(path = dir_nc), common))
  met_gr <- do.call(extract_era5_hourly_met, c(list(path = dir_gr), common))

  expect_equal(met_gr$Date, met_nc$Date)
  expect_equal(met_gr$MET_tmpair, met_nc$MET_tmpair, tolerance = 1e-4)
})

test_that(".grib files are dispatched to the terra backend", {
  dir <- tempfile("era5gr"); dir.create(dir)
  f <- file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.grib")

  if (!requireNamespace("terra", quietly = TRUE)) {
    file.create(f)
    expect_error(
      extract_era5_hourly_met(path = dir, lon = 176.2, lat = -38.0,
                              variables = "2m_temperature", years = 2024,
                              verbose = FALSE),
      "terra")
    return(invisible())
  }

  # A real multi-step GRIB: if its timestamps survive the round-trip we get a
  # full series, otherwise the guard in read_file_grib fires. Either way the
  # .grib path went through terra, not ncdf4.
  g <- make_grid()
  write_grib(f, g, field(g, 288, 4))

  call_it <- function()
    extract_era5_hourly_met(path = dir, lon = 176.2, lat = -38.0,
                            variables = "2m_temperature", method = "nearest",
                            years = 2024, tz = "UTC", fill_gaps = FALSE,
                            verbose = FALSE)

  if (grib_time_roundtrips(f, g)) {
    met <- call_it()
    expect_identical(nrow(met), length(g$time))
    expect_true(all(met$MET_tmpair > 5 & met$MET_tmpair < 30))
  } else {
    expect_error(call_it(), "GRIB")
  }
})

test_that("extract_era5_lake_met() takes a polygon and labels the result", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("sf")

  g <- make_grid()
  dir <- tempfile("era5lake"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  poly <- readRDS(system.file("extdata", "rotorua_lake_shape.rds",
                              package = "metscale"))

  met <- extract_era5_lake_met(
    poly, path = dir, variables = "2m_temperature",
    id = "LID 1", name = "Rotorua",
    tz = "UTC", fill_gaps = FALSE, verbose = FALSE)

  expect_s3_class(met, "data.frame")
  expect_identical(nrow(met), length(g$time))
  expect_identical(attr(met, "lake_id"), "LID 1")
  expect_identical(attr(met, "lake_name"), "Rotorua")
  expect_identical(attr(met, "method"), "area")   # the wrapper's default
})

test_that("extract_era5_lake_met() rejects non-geometry input", {
  skip_if_not_installed("sf")
  expect_error(extract_era5_lake_met(42, path = "."), "sf/sfc")
  expect_error(extract_era5_lake_met("no_such_file.gpkg", path = "."),
               "not found")
})
