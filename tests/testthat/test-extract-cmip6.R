## Synthetic single-variable projection netCDF, CF calendar + "<unit> since".
make_cmip6_nc <- function(path, varname = "tas", var_units = "K",
                          calendar = "365_day",
                          time_units = "days since 2000-01-01",
                          lon = seq(170, 172, by = 0.5),
                          lat = seq(-37, -39, by = -0.5),   # descending, like CCAM
                          nt = 40,
                          field = function(x, y, t) 250 + 2 * x - 3 * y + 0.1 * t) {
  td <- ncdf4::ncdim_def("time", time_units, seq_len(nt) - 1,
                         unlim = FALSE, calendar = calendar)
  xd <- ncdf4::ncdim_def("longitude", "degrees_east", lon)
  yd <- ncdf4::ncdim_def("latitude", "degrees_north", lat)
  vd <- ncdf4::ncvar_def(varname, var_units, list(xd, yd, td), -9999,
                         prec = "double")
  nc <- ncdf4::nc_create(path, vd)
  A <- array(0, c(length(lon), length(lat), nt))
  for (k in seq_len(nt))
    A[, , k] <- outer(lon, lat, function(x, y) field(x, y, k - 1) + 0 * x)
  ncdf4::ncvar_put(nc, vd, A)
  ncdf4::nc_close(nc)
  path
}

test_that("bilinear interpolation is exact for a linear field", {
  f <- function(x, y, t) 250 + 2 * x - 3 * y + 0.1 * t
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, field = f)

  lon0 <- 170.7; lat0 <- -37.6
  out <- extract_cmip6_point(p, lon = lon0, lat = lat0, vars = "MET_tmpair",
                             verbose = FALSE)

  expect_s3_class(out$Date, "Date")
  expect_identical(unique(out$experiment), "historical")
  expect_equal(nrow(out), 40)
  expect_equal(out$MET_tmpair,
               (250 + 2 * lon0 - 3 * lat0 + 0.1 * (seq_len(40) - 1)) - 273.15,
               tolerance = 1e-8)
})

test_that("nearest returns the containing grid node", {
  f <- function(x, y, t) 100 * x + y + t
  p <- file.path(tempdir(), "rsds_ssp245_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, varname = "rsds", var_units = "W m-2", field = f)

  ## nearest node to (170.7, -37.6) is (170.5, -37.5)
  out <- extract_cmip6_point(p, lon = 170.7, lat = -37.6, vars = "MET_radswd",
                             method = "nearest", verbose = FALSE)
  expect_equal(out$MET_radswd[1], 100 * 170.5 + (-37.5) + 0, tolerance = 1e-8)
})

test_that("365_day calendar decodes to real dates with no 29 February", {
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  ## 400 steps from 2000-01-01 spans past a real leap day
  make_cmip6_nc(p, nt = 400, time_units = "days since 2000-01-01",
                calendar = "365_day")
  out <- extract_cmip6_point(p, lon = 171, lat = -38, vars = "MET_tmpair",
                             verbose = FALSE)
  expect_equal(out$Date[1], as.Date("2000-01-01"))
  expect_false(any(format(out$Date, "%m-%d") == "02-29"))
  ## day 365 (index 366) is exactly one 365-day year on
  expect_equal(out$Date[366], as.Date("2001-01-01"))
})

test_that("360_day calendar gives 30-day months", {
  p <- file.path(tempdir(), "pr_ssp585_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, varname = "pr", var_units = "mm/day", nt = 90,
                time_units = "days since 2000-01-01", calendar = "360_day")
  out <- extract_cmip6_point(p, lon = 171, lat = -38, vars = "MET_pprain",
                             verbose = FALSE)
  ## 30 steps in -> 1 month on; 60 steps in -> 2 months on
  expect_equal(out$Date[31], as.Date("2000-02-01"))
  expect_equal(out$Date[61], as.Date("2000-03-01"))
})

test_that("kg m-2 s-1 precipitation is converted to mm/day", {
  p <- file.path(tempdir(), "pr_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, varname = "pr", var_units = "kg m-2 s-1", nt = 10,
                field = function(x, y, t) 1e-5)
  out <- extract_cmip6_point(p, lon = 171, lat = -38, vars = "MET_pprain",
                             verbose = FALSE)
  expect_equal(out$MET_pprain, rep(1e-5 * 86400, 10), tolerance = 1e-12)
})

test_that("experiments stack and can be filtered", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"), nt = 20)
  make_cmip6_nc(file.path(d, "tas_ssp245_MODEL_daily.nc"),     nt = 20)
  make_cmip6_nc(file.path(d, "tas_ssp585_MODEL_daily.nc"),     nt = 20)

  all3 <- extract_cmip6_point(d, lon = 171, lat = -38, vars = "MET_tmpair",
                              verbose = FALSE)
  expect_setequal(unique(all3$experiment), c("historical", "ssp245", "ssp585"))
  expect_equal(nrow(all3), 60)

  two <- extract_cmip6_point(d, lon = 171, lat = -38, vars = "MET_tmpair",
                             experiments = c("historical", "ssp585"),
                             verbose = FALSE)
  expect_setequal(unique(two$experiment), c("historical", "ssp585"))
})

test_that("mixing MET_* and CMIP names is rejected", {
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, nt = 5)
  expect_error(
    extract_cmip6_point(p, lon = 171, lat = -38,
                        vars = c("MET_tmpair", "pr"), verbose = FALSE),
    "do not mix")
})
