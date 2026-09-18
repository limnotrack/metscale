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
  out <- extract_climate_point(p, lon = lon0, lat = lat0, vars = "MET_tmpair",
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
  out <- extract_climate_point(p, lon = 170.7, lat = -37.6, vars = "MET_radswd",
                             method = "nearest", verbose = FALSE)
  expect_equal(out$MET_radswd[1], 100 * 170.5 + (-37.5) + 0, tolerance = 1e-8)
})

test_that("365_day calendar decodes to real dates with no 29 February", {
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  ## 400 steps from 2000-01-01 spans past a real leap day
  make_cmip6_nc(p, nt = 400, time_units = "days since 2000-01-01",
                calendar = "365_day")
  out <- extract_climate_point(p, lon = 171, lat = -38, vars = "MET_tmpair",
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
  out <- extract_climate_point(p, lon = 171, lat = -38, vars = "MET_pprain",
                             verbose = FALSE)
  ## 30 steps in -> 1 month on; 2000 is a leap year so real Feb has 29 days,
  ## the model's 30th Feb day clamps onto (and is deduped with) Feb 29,
  ## shifting March 1 to row 60 instead of 61
  expect_equal(out$Date[31], as.Date("2000-02-01"))
  expect_equal(out$Date[60], as.Date("2000-03-01"))
  expect_equal(nrow(out), 89)
})

test_that("kg m-2 s-1 precipitation is converted to mm/day", {
  p <- file.path(tempdir(), "pr_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, varname = "pr", var_units = "kg m-2 s-1", nt = 10,
                field = function(x, y, t) 1e-5)
  out <- extract_climate_point(p, lon = 171, lat = -38, vars = "MET_pprain",
                             verbose = FALSE)
  expect_equal(out$MET_pprain, rep(1e-5 * 86400, 10), tolerance = 1e-12)
})

test_that("experiments stack and can be filtered", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"), nt = 20)
  make_cmip6_nc(file.path(d, "tas_ssp245_MODEL_daily.nc"),     nt = 20)
  make_cmip6_nc(file.path(d, "tas_ssp585_MODEL_daily.nc"),     nt = 20)

  all3 <- extract_climate_point(d, lon = 171, lat = -38, vars = "MET_tmpair",
                              verbose = FALSE)
  expect_setequal(unique(all3$experiment), c("historical", "ssp245", "ssp585"))
  expect_equal(nrow(all3), 60)

  two <- extract_climate_point(d, lon = 171, lat = -38, vars = "MET_tmpair",
                             experiments = c("historical", "ssp585"),
                             verbose = FALSE)
  expect_setequal(unique(two$experiment), c("historical", "ssp585"))
})

test_that("duplicate calendar-clamp dates are deduped, not cartesian-multiplied", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  ## 2001 is not a leap year: 360_day model-days 28/29/30 of Feb (real Feb has
  ## only 28 days) all clamp onto 2001-02-28, in *both* variable files
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"),
                varname = "tas", nt = 60, calendar = "360_day",
                time_units = "days since 2001-01-01")
  make_cmip6_nc(file.path(d, "pr_historical_MODEL_daily.nc"),
                varname = "pr", var_units = "mm/day", nt = 60,
                calendar = "360_day", time_units = "days since 2001-01-01")

  out <- extract_climate_point(d, lon = 171, lat = -38,
                             vars = c("MET_tmpair", "MET_pprain"),
                             verbose = FALSE)

  ## 30 unique Jan dates + 28 unique Feb dates (28/29/30 collapse to Feb 28)
  expect_equal(nrow(out), 58)
  expect_false(anyDuplicated(out$Date) > 0)
  expect_false(anyNA(out$MET_tmpair))
  expect_false(anyNA(out$MET_pprain))
})

test_that("mismatched date coverage reports and totals NA after merge", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"),
                varname = "tas", nt = 10, time_units = "days since 2000-01-01")
  make_cmip6_nc(file.path(d, "pr_historical_MODEL_daily.nc"),
                varname = "pr", var_units = "mm/day", nt = 15,
                time_units = "days since 2000-01-01")

  expect_message(
    out <- extract_climate_point(d, lon = 171, lat = -38,
                               vars = c("MET_tmpair", "MET_pprain"),
                               verbose = TRUE),
    "MET_tmpair: 5 NA after merge")

  expect_equal(nrow(out), 15)
  expect_equal(sum(is.na(out$MET_tmpair)), 5)
  expect_true(all(!is.na(out$MET_pprain)))

  expect_error(
    extract_climate_point(d, lon = 171, lat = -38,
                        vars = c("MET_tmpair", "MET_pprain"),
                        strict = TRUE, verbose = FALSE),
    "MET_tmpair: 5 NA after merge")
})

test_that("missing calendar attribute warns and falls back to standard", {
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  td <- ncdf4::ncdim_def("time", "days since 2000-01-01", seq_len(5) - 1,
                         unlim = FALSE)                # no 'calendar' attribute
  xd <- ncdf4::ncdim_def("longitude", "degrees_east", seq(170, 172, by = 0.5))
  yd <- ncdf4::ncdim_def("latitude", "degrees_north", seq(-37, -39, by = -0.5))
  vd <- ncdf4::ncvar_def("tas", "K", list(xd, yd, td), -9999, prec = "double")
  nc <- ncdf4::nc_create(p, vd)
  ncdf4::ncvar_put(nc, vd, array(280, c(5, 5, 5)))
  ncdf4::nc_close(nc)

  expect_warning(
    out <- extract_climate_point(p, lon = 171, lat = -38, vars = "MET_tmpair",
                               verbose = FALSE),
    "no 'calendar' attribute")
  expect_equal(nrow(out), 5)
  expect_equal(out$Date[1], as.Date("2000-01-01"))
})

test_that("monthly climatology weights every model day equally, unlike the merged daily series", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  ## 2001 is not a leap year; model-day value == model-day index (t), so each
  ## month's true equal-weighted mean is easy to compute by hand
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"), varname = "tas",
                nt = 60, calendar = "360_day",
                time_units = "days since 2001-01-01",
                field = function(x, y, t) t)

  clim <- climate_point_monthly_climatology(d, lon = 171, lat = -38,
                                          vars = "MET_tmpair", verbose = FALSE)
  expect_setequal(clim$month, 1:2)

  ## January: no clamping (30 model days -> 30 distinct real days)
  jan <- clim$value[clim$month == 1]
  expect_equal(jan, mean(0:29) - 273.15, tolerance = 1e-8)

  ## February: 30 model days clamp onto 28 real days (dy 28/29/30 -> Feb 28);
  ## the true equal-weighted mean over all 30 raw model-day values (30:59)
  feb <- clim$value[clim$month == 2]
  expect_equal(feb, mean(30:59) - 273.15, tolerance = 1e-8)

  ## contrast with extract_climate_point()'s merged/deduped daily series: its
  ## clamped Feb 28 row is already an average of 3 model days, so a naive
  ## monthly mean taken from it down-weights those 3 days to 1/28th instead
  ## of 3/30ths of the month, and disagrees with the true equal-weighted mean
  daily <- extract_climate_point(d, lon = 171, lat = -38, vars = "MET_tmpair",
                               verbose = FALSE)
  naive_feb <- mean(daily$MET_tmpair[format(daily$Date, "%m") == "02"])
  expect_false(isTRUE(all.equal(naive_feb, feb)))
})

test_that("monthly climatology 'years' argument restricts the reference window", {
  d <- tempfile("cmip6"); dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  ## 730 days from 2000-01-01 (standard calendar) spans 2000 and most of 2001
  make_cmip6_nc(file.path(d, "tas_historical_MODEL_daily.nc"), varname = "tas",
                nt = 730, calendar = "standard",
                time_units = "days since 2000-01-01",
                field = function(x, y, t) t)

  clim_2000 <- climate_point_monthly_climatology(d, lon = 171, lat = -38,
                                               vars = "MET_tmpair",
                                               years = 2000, verbose = FALSE)
  clim_2001 <- climate_point_monthly_climatology(d, lon = 171, lat = -38,
                                               vars = "MET_tmpair",
                                               years = 2001, verbose = FALSE)
  ## same calendar month, different year -> different (later, warmer) mean
  expect_true(all(clim_2001$value[clim_2001$month %in% 1:11] >
                  clim_2000$value[clim_2000$month %in% 1:11]))
})

test_that("mixing MET_* and CMIP names is rejected", {
  p <- file.path(tempdir(), "tas_historical_MODEL_daily.nc")
  on.exit(unlink(p))
  make_cmip6_nc(p, nt = 5)
  expect_error(
    extract_climate_point(p, lon = 171, lat = -38,
                        vars = c("MET_tmpair", "pr"), verbose = FALSE),
    "do not mix")
})
