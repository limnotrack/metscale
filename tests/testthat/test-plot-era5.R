# plot_era5() is a quick-look viewer for an ERA5 GRIB / netCDF file. Tests
# draw to a throw-away PNG device and inspect the returned summary + the
# series / maps attributes.

grib_fixture <- function() {
  f <- system.file(
    "extdata/era5/reanalysis-era5-land_2m_temperature_hourly_2024_1_toba.grib",
    package = "metscale")
  if (!nzchar(f)) skip("bundled ERA5 GRIB fixture not installed")
  f
}

write_mini_nc <- function(path, vars = c("t2m", "sp"), n_hours = 24) {
  skip_if_not_installed("ncdf4")
  lon <- seq(176.0, 176.3, by = 0.1)
  lat <- seq(-38.2, -37.9, by = 0.1)
  tm  <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour",
             length.out = n_hours)
  dl <- ncdf4::ncdim_def("longitude", "degrees_east", lon)
  da <- ncdf4::ncdim_def("latitude", "degrees_north", lat)
  dt <- ncdf4::ncdim_def("valid_time", "seconds since 1970-01-01 00:00:00",
                         as.numeric(tm))
  defs <- lapply(vars, function(v)
    ncdf4::ncvar_def(v, "unit", list(dl, da, dt), missval = -9999))
  nc <- ncdf4::nc_create(path, defs)
  on.exit(ncdf4::nc_close(nc))
  arr <- array(stats::runif(length(lon) * length(lat) * n_hours, 280, 300),
               c(length(lon), length(lat), n_hours))
  for (i in seq_along(defs)) ncdf4::ncvar_put(nc, defs[[i]], arr * i)
  path
}

## open a throw-away PNG device; caller registers cleanup with on.exit()
png_dev <- function() {
  tmp <- tempfile(fileext = ".png")
  grDevices::png(tmp)
  tmp
}

test_that("plot_era5() summarises a GRIB file and attaches series + maps", {
  skip_if_not_installed("terra")
  f <- grib_fixture()
  tmp <- png_dev(); on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)

  s <- plot_era5(f, verbose = FALSE)

  expect_s3_class(s, "data.frame")
  expect_equal(nrow(s), 1L)
  expect_identical(s$variable, "2t")
  expect_equal(s$n_layers, 744L)
  expect_true(s$min <= s$mean && s$mean <= s$max)

  ser <- attr(s, "series")
  expect_named(ser, "2t")
  expect_equal(nrow(ser[["2t"]]), 744L)
  expect_true(all(c("time", "value") %in% names(ser[["2t"]])))

  m <- attr(s, "maps")[["2t"]]
  expect_s4_class(m, "SpatRaster")
  expect_equal(terra::nlyr(m), 1L)          # aggregated to one layer
})

test_that("plot_era5() maps a single step for `time` and honours negatives", {
  skip_if_not_installed("terra")
  f <- grib_fixture()
  tmp <- png_dev(); on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)

  s1 <- plot_era5(f, time = 1L, verbose = FALSE)
  s2 <- plot_era5(f, time = -1L, verbose = FALSE)

  v1 <- attr(s1, "series")[["2t"]]$value[1]
  vN <- attr(s2, "series")[["2t"]]$value
  expect_equal(terra::nlyr(attr(s1, "maps")[["2t"]]), 1L)
  # first vs last hour of the month differ
  expect_false(isTRUE(all.equal(v1, vN[length(vN)])))
})

test_that("plot_era5(point=) returns a point series, not the grid mean", {
  skip_if_not_installed("terra")
  f <- grib_fixture()
  tmp <- png_dev(); on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)

  g <- plot_era5(f, verbose = FALSE)
  p <- plot_era5(f, point = c(98.6, 2.6), verbose = FALSE)

  gv <- attr(g, "series")[["2t"]]$value
  pv <- attr(p, "series")[["2t"]]$value
  expect_length(pv, length(gv))
  expect_true(all(is.finite(pv)))
  expect_false(isTRUE(all.equal(gv, pv)))
})

test_that("plot_era5() splits a multi-variable netCDF and filters with `var`", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ncdf4")
  f <- write_mini_nc(tempfile(fileext = ".nc"))
  tmp <- png_dev(); on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)

  s <- plot_era5(f, verbose = FALSE)
  expect_setequal(s$variable, c("t2m", "sp"))

  s1 <- plot_era5(f, var = "SP", verbose = FALSE)   # case-insensitive
  expect_identical(s1$variable, "sp")

  expect_error(plot_era5(f, var = "nope", verbose = FALSE), "not found|found")
})

test_that("plot_era5(engine='ggplot2') returns a ggplot with the attrs", {
  skip_if_not_installed("terra")
  skip_if_not_installed("ggplot2")
  f <- grib_fixture()
  tmp <- png_dev(); on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)

  p <- plot_era5(f, engine = "ggplot2", verbose = FALSE)
  expect_s3_class(p, "ggplot")
  expect_s3_class(attr(p, "summary"), "data.frame")
  expect_named(attr(p, "series"), "2t")
})

test_that("plot_era5() errors on a missing file", {
  expect_error(plot_era5(tempfile(fileext = ".grib")), "not found")
})
