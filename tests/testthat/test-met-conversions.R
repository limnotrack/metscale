test_that("humidity conversions round-trip", {
  airt <- c(-5, 0, 10, 20, 30)
  relh <- c(40, 60, 75, 90, 55)
  expect_equal(dewpoint_to_rh(airt, rh_to_dewpoint(airt, relh)), relh,
               tolerance = 1e-8)
  expect_true(all(rh_to_dewpoint(airt, relh) <= airt + 1e-8))
})

test_that("wind vector conversions are mutually inverse", {
  d <- c(0, 45, 90, 135, 180, 225, 270, 315)
  s <- c(1, 3, 5, 2, 6, 4, 7, 2)
  uv <- ds2uv(d, s)
  ds <- uv2ds(uv[, "u"], uv[, "v"])
  expect_equal(as.numeric(ds[, "dir"]), d, tolerance = 1e-8)
  expect_equal(as.numeric(ds[, "speed"]), s, tolerance = 1e-8)
})

test_that("wind components use the meteorological from-convention", {
  ## a southerly (from 180) blows towards the north: v positive, u zero
  uv <- ds2uv(180, 5)
  expect_equal(as.numeric(uv[, "u"]), 0, tolerance = 1e-8)
  expect_equal(as.numeric(uv[, "v"]), 5, tolerance = 1e-8)
  ## a westerly (from 270) blows towards the east: u positive
  uv <- ds2uv(270, 5)
  expect_equal(as.numeric(uv[, "u"]), 5, tolerance = 1e-8)
  expect_equal(as.numeric(uv[, "v"]), 0, tolerance = 1e-8)
})

test_that("pressure is in Pa and converts back and forth", {
  p <- station_pressure(15, 70, elev = 280)
  expect_gt(p, 90000); expect_lt(p, 101325)      # Pa, not hPa
  expect_equal(station_from_mslp(mslp_from_station(p, 280, 15), 280, 15), p,
               tolerance = 1e-6)
  expect_equal(station_pressure(15, 70, elev = 0), 101325, tolerance = 1)
})

test_that("longwave is physically plausible and increases with cloud", {
  lw <- calc_in_lwr(cc = c(0, 0.5, 1), airt = 15, relh = 70)
  expect_true(all(lw > 150 & lw < 450))
  expect_true(all(diff(lw) > 0))
})

test_that("calc_humidity_vars is vectorised and internally consistent", {
  h <- calc_humidity_vars(hum = c(50, 70, 90), hum_method = 1,
                          airp = 101325, tw = 18, ta = 15)
  expect_length(h$ea, 3)
  expect_true(all(diff(h$ea) > 0))               # more humid -> more vapour
  expect_true(all(h$rhoa > 1.0 & h$rhoa < 1.4))  # air density kg/m3
  expect_true(all(h$qa < h$qs))
})

test_that("wind_at_height: log profile 2m -> 10m over water", {
  ## u(10)/u(2) = log(10/z0) / log(2/z0), z0 = 2e-4
  f <- log(10 / 2e-4) / log(2 / 2e-4)
  expect_equal(wind_at_height(5, from = 2), 5 * f)
  expect_gt(f, 1.15); expect_lt(f, 1.20)
  expect_equal(wind_at_height(c(0, 3, 8), from = 2),
               c(0, 3, 8) * f, tolerance = 1e-12)
  expect_equal(wind_at_height(5, from = 10, to = 10), 5)   # no-op
})

test_that("wind_at_height: power law and charnock", {
  expect_equal(wind_at_height(5, from = 2, method = "power"), 5 * 5^0.11)
  ch <- wind_at_height(c(2, 10, 20), from = 2, z0 = "charnock")
  expect_length(ch, 3)
  expect_true(all(ch > c(2, 10, 20)))                      # 10 m windier
  ## speed-dependent: the multiplicative factor grows with wind speed
  fac <- ch / c(2, 10, 20)
  expect_true(all(diff(fac) > 0))
})

test_that("met_wind_at_height scales speed and components, keeps direction", {
  d0 <- ds2uv(c(45, 200, 310), c(3, 5, 7))
  met <- data.frame(MET_wndspd = c(3, 5, 7),
                    MET_wnduvu = d0[, "u"], MET_wnduvv = d0[, "v"])
  out <- met_wind_at_height(met, from = 2)
  f <- log(10 / 2e-4) / log(2 / 2e-4)
  expect_equal(out$MET_wndspd, c(3, 5, 7) * f)
  expect_equal(sqrt(out$MET_wnduvu^2 + out$MET_wnduvv^2), out$MET_wndspd,
               tolerance = 1e-9)
  expect_equal(uv2ds(out$MET_wnduvu, out$MET_wnduvv)[, "dir"],
               uv2ds(met$MET_wnduvu, met$MET_wnduvv)[, "dir"], tolerance = 1e-9)
  expect_equal(attr(out, "wind_height"), 10)
})

test_that("prepare_obs_met wind_height adjusts the wind on the way in", {
  raw <- data.frame(time = seq(as.POSIXct("2024-01-01", tz = "UTC"),
                               by = "hour", length.out = 6),
                    WindSpeed = c(2, 3, 4, 5, 6, 7),
                    AirTemp = 15)
  a <- suppressMessages(prepare_obs_met(raw, tz = "UTC", verbose = FALSE))
  b <- suppressMessages(prepare_obs_met(raw, tz = "UTC", wind_height = 2,
                                        verbose = FALSE))
  f <- log(10 / 2e-4) / log(2 / 2e-4)
  expect_equal(b$MET_wndspd, a$MET_wndspd * f, tolerance = 1e-9)
})
