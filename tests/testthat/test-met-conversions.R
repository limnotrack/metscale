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
