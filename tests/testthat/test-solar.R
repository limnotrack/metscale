TZ  <- "Etc/GMT-12"          # fixed NZST
LAT <- -38.079
LON <- 176.2717

test_that("clear-sky shortwave peaks at local solar noon", {
  t <- seq(as.POSIXct("2024-01-15 00:00", tz = TZ), by = "hour", length.out = 24)
  cs <- clear_sky_swr(t, LAT, LON)
  expect_equal(as.integer(format(t[which.max(cs)], "%H", tz = TZ)), 12L)
  expect_gt(max(cs), 900)
  expect_lt(max(cs), 1200)
})

test_that("solar geometry depends on the instant, not the tz label", {
  t     <- seq(as.POSIXct("2024-06-15 00:00", tz = TZ), by = "hour", length.out = 24)
  t_utc <- as.POSIXct(format(t, tz = "UTC"), tz = "UTC")   # same instants
  expect_equal(clear_sky_swr(t, LAT, LON), clear_sky_swr(t_utc, LAT, LON))
  expect_equal(solar_zenith_angle(t, LAT, LON),
               solar_zenith_angle(t_utc, LAT, LON))
})

test_that("night is exactly dark and summer beats winter", {
  jan <- clear_sky_swr(seq(as.POSIXct("2024-01-15", tz = TZ), by = "hour",
                           length.out = 24), LAT, LON)
  jul <- clear_sky_swr(seq(as.POSIXct("2024-07-15", tz = TZ), by = "hour",
                           length.out = 24), LAT, LON)
  expect_true(any(jan == 0))
  expect_gt(max(jan), max(jul))
  expect_true(all(jan >= 0))
})

test_that("zenith is 90 degrees at night and smallest near noon", {
  t <- seq(as.POSIXct("2024-01-15 00:00", tz = TZ), by = "hour", length.out = 24)
  z <- solar_zenith_angle(t, LAT, LON)
  expect_lte(max(z), 90 + 1e-8)
  expect_equal(as.integer(format(t[which.min(z)], "%H", tz = TZ)), 12L)
})

test_that("estimate_hourly_swr conserves the daily mean at both timesteps", {
  daily <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 30),
                      MET_radswd = seq(80, 320, length.out = 30))
  for (ts in c("hour", "3hour")) {
    hr <- estimate_hourly_swr(daily, LAT, LON, tz = TZ, timestep = ts)
    expect_equal(nrow(hr), nrow(daily) * if (ts == "hour") 24 else 8)
    back <- as.numeric(tapply(hr$MET_radswd, as.Date(hr$Date, tz = TZ), mean))
    expect_equal(back, daily$MET_radswd, tolerance = 1e-8)
    expect_true(all(hr$MET_radswd >= 0))
  }
})

test_that("hour-ending is the default and shifts the peak by one step", {
  daily <- data.frame(Date = as.Date("2024-01-15") + 0:2, MET_radswd = 300)
  ending  <- estimate_hourly_swr(daily, LAT, LON, tz = TZ, interval = "ending")
  instant <- estimate_hourly_swr(daily, LAT, LON, tz = TZ, interval = "instant")
  pk <- function(x) as.integer(format(x$Date[which.max(x$MET_radswd)], "%H", tz = TZ))
  expect_equal(pk(ending), 13L)     # the hour 12:00-13:00 contains solar noon
  expect_equal(pk(instant), 12L)
})
