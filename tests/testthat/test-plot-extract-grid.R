# plot_extract_grid() draws the ERA5 grid + geometry from the same file
# discovery / cell-selection machinery the extractors use. Tiny netCDF
# fixtures, mirroring the ones in test-extract-era5.R.

make_grid <- function(start = "2024-01-01 00:00", n_hours = 72) {
  list(
    lon = seq(176.0, 176.4, by = 0.1),
    lat = seq(-38.2, -37.8, by = 0.1),
    time = seq(as.POSIXct(start, tz = "UTC"), by = "hour",
               length.out = n_hours)
  )
}

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

test_that("plot_extract_grid() returns a ggplot with grid / weights attrs (point)", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")

  g <- make_grid()
  dir <- tempfile("pegnc"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  p <- plot_extract_grid(dir, lon = 176.22, lat = -38.03, method = "bilinear")

  expect_s3_class(p, "ggplot")
  gr <- attr(p, "grid"); w <- attr(p, "weights")
  expect_s3_class(gr, "sf")
  expect_true(all(c("ix", "iy", "weight", "selected", "land") %in% names(gr)))
  expect_equal(nrow(w), 4L)                       # bilinear -> 4 cells
  expect_equal(sum(w$w), 1, tolerance = 1e-8)
  expect_equal(sum(gr$selected), 4L)
  expect_identical(normalizePath(attr(p, "file")),
                   normalizePath(file.path(dir,
                     "nz_era5-land_2024_01_2m_temperature_daily.nc")))
})

test_that("plot_extract_grid() previews an area-weighted polygon selection", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")

  g <- make_grid()
  dir <- tempfile("pegpoly"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))
  poly <- readRDS(system.file("extdata", "rotorua_lake_shape.rds",
                              package = "metscale"))

  p <- plot_extract_grid(dir, geom = poly, method = "area")
  w <- attr(p, "weights")

  expect_s3_class(p, "ggplot")
  expect_gte(nrow(w), 1L)
  expect_equal(sum(w$w), 1, tolerance = 1e-8)
  # every picked cell is also flagged in the drawn grid
  gr <- attr(p, "grid")
  expect_setequal(paste(w$ix, w$iy), paste(gr$ix, gr$iy)[gr$selected])
})

test_that("plot_extract_grid() warns instead of erroring on a far point", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("sf")
  skip_if_not_installed("ggplot2")

  g <- make_grid()
  dir <- tempfile("pegfar"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  expect_warning(
    p <- plot_extract_grid(dir, lon = 178.0, lat = -38.0, method = "nearest"),
    "max_dist_km")
  expect_s3_class(p, "ggplot")
  expect_equal(nrow(attr(p, "weights")), 1L)
})

test_that("plot_extract_grid(engine = 'base') draws and returns the grid", {
  skip_if_not_installed("ncdf4")
  skip_if_not_installed("sf")

  g <- make_grid()
  dir <- tempfile("pegbase"); dir.create(dir)
  write_nc(file.path(dir, "nz_era5-land_2024_01_2m_temperature_daily.nc"),
           g, field(g, 288, 4))

  tmp <- tempfile(fileext = ".png"); grDevices::png(tmp)
  on.exit({ grDevices::dev.off(); unlink(tmp) }, add = TRUE)
  out <- plot_extract_grid(dir, lon = 176.22, lat = -38.03,
                           method = "nearest", engine = "base")

  expect_s3_class(out, "sf")
  expect_equal(nrow(attr(out, "weights")), 1L)
})
