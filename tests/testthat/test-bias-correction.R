TZ <- "Etc/GMT-12"

## A synthetic "reanalysis" record with a diurnal and seasonal cycle.
fake_era5 <- function(years = 2020:2022) {
  t <- seq(as.POSIXct(paste0(min(years), "-01-01 00:00"), tz = TZ),
           as.POSIXct(paste0(max(years), "-12-31 23:00"), tz = TZ), by = "hour")
  h <- as.integer(format(t, "%H", tz = TZ))
  d <- as.integer(format(t, "%j", tz = TZ))
  seas <- sin(2 * pi * (d - 300) / 365)
  out <- data.frame(
    Date       = t,
    MET_tmpair = 13 + 6 * seas + 4 * sin((h - 9) / 24 * 2 * pi) + rnorm(length(t), 0, 1),
    MET_wndspd = pmax(0.1, 3.5 + 1.2 * sin((h - 12) / 24 * 2 * pi) + rnorm(length(t), 0, 0.8)),
    MET_radswd = pmax(0, (700 + 250 * seas) * pmax(0, sin((h - 6) / 12 * pi))))
  attr(out, "tz") <- TZ
  out
}

test_that("a known monthly perturbation is recovered and reversed", {
  set.seed(11)
  era5 <- fake_era5()
  m <- as.integer(format(era5$Date, "%m", tz = TZ))
  true_dT <- c(-1.8, -1.6, -1.2, -0.8, -0.4, 0, 0.2, 0.2, 0, -0.4, -0.9, -1.5)
  true_fW <- c(1.5, 1.5, 1.45, 1.4, 1.35, 1.3, 1.3, 1.35, 1.4, 1.45, 1.5, 1.55)

  obs <- data.frame(
    Date       = era5$Date,
    MET_tmpair = era5$MET_tmpair + true_dT[m] + rnorm(nrow(era5), 0, 0.5),
    MET_wndspd = pmax(0, era5$MET_wndspd * true_fW[m] + rnorm(nrow(era5), 0, 0.3)))
  attr(obs, "tz") <- TZ

  bc <- fit_met_bias_correction(era5, obs, verbose = FALSE)
  expect_s3_class(bc, "met_biascorr")
  expect_lt(max(abs(bc$models$MET_tmpair$month_factor - true_dT)), 0.15)
  expect_lt(max(abs(bc$models$MET_wndspd$month_factor - true_fW)), 0.05)

  ## default transforms: additive for temperature, ratio for wind
  expect_identical(bc$models$MET_tmpair$transform, "additive")
  expect_identical(bc$models$MET_wndspd$transform, "ratio")

  corrected <- apply_met_bias_correction(era5, bc, verbose = FALSE)
  expect_lt(abs(mean(corrected$MET_tmpair) - mean(obs$MET_tmpair)), 0.05)
  expect_true(all(corrected$MET_wndspd >= 0))

  ## the correction must improve out-of-sample skill
  cvc <- bc$skill[bc$skill$stage == "cv_corrected", ]
  cvr <- bc$skill[bc$skill$stage == "cv_raw", ]
  expect_true(nrow(cvc) > 0)
  expect_true(all(cvc$rmse < cvr$rmse))
  expect_true(all(abs(cvc$bias) < abs(cvr$bias)))
})

test_that("every method runs and reduces bias", {
  set.seed(12)
  era5 <- fake_era5(2020:2021)
  obs <- data.frame(Date = era5$Date,
                    MET_tmpair = era5$MET_tmpair * 1.05 - 1.2 + rnorm(nrow(era5), 0, 0.4))
  attr(obs, "tz") <- TZ
  for (meth in c("scale", "variance", "linear", "eqm", "qdm")) {
    bc <- fit_met_bias_correction(era5, obs, method = meth, cv = "none",
                                  verbose = FALSE)
    s <- bc$skill[bc$skill$variable == "MET_tmpair", ]
    expect_lt(abs(s$bias[s$stage == "corrected"]),
              abs(s$bias[s$stage == "raw"]) + 1e-8,
              label = paste("bias reduced by", meth))
  }
})

test_that("a per-variable transform vector overrides the defaults", {
  set.seed(13)
  era5 <- fake_era5(2020:2021)
  obs <- data.frame(Date = era5$Date,
                    MET_radswd = era5$MET_radswd * 0.9,
                    MET_tmpair = era5$MET_tmpair * 1.02)
  attr(obs, "tz") <- TZ
  bc <- fit_met_bias_correction(era5, obs, cv = "none",
                                transform = c(MET_radswd = "additive"),
                                verbose = FALSE)
  expect_identical(bc$models$MET_radswd$transform, "additive")
  expect_identical(bc$models$MET_tmpair$transform, "additive")  # default
})

test_that("prepare_obs_met standardises, derives and resamples", {
  set.seed(14)
  t <- seq(as.POSIXct("2024-01-01 00:00", tz = TZ), by = "15 min",
           length.out = 4 * 24 * 10)
  raw <- data.frame(timestamp = t,
                    AirTemp   = rnorm(length(t), 288, 3),      # Kelvin
                    WindSpeed = runif(length(t), 0, 20),        # km/h
                    RelHum    = runif(length(t), 0.4, 0.99),    # fraction
                    Rain      = 0.05)
  o <- prepare_obs_met(raw, tz = TZ, resample = "hour", station = "buoy",
                       verbose = FALSE)
  expect_equal(attr(o, "resolution"), "hourly")
  expect_equal(attr(o, "station"), "buoy")
  expect_true(all(o$MET_tmpair < 60))            # K -> degC
  expect_true(max(o$MET_humrel) > 1)             # fraction -> %
  expect_true("MET_tmpdew" %in% names(o))        # derived
  expect_true(all(diff(as.numeric(o$Date)) == 3600))
  ## hour-ending (the default): the record at 00:00 is the only one in the
  ## first bin, then four 15-minute records per full hour
  expect_equal(o$MET_pprain[1], 0.05, tolerance = 1e-8)
  expect_equal(o$MET_pprain[2], 0.20, tolerance = 1e-8)
  expect_equal(as.integer(format(o$Date[2], "%H", tz = TZ)), 1L)
})

test_that("hourly obs stay hourly even with time-less midnight rows", {
  n <- 24 * 15
  t <- seq(as.POSIXct("2022-02-21 00:00", tz = TZ), by = "hour", length.out = n)
  ts <- format(t, "%Y-%m-%d %H:%M:%S")
  ## some exports write midnight as a bare date - this used to collapse the
  ## whole column to dates and drop 23/24 of the rows
  ts[format(t, "%H") == "00"] <- format(t[format(t, "%H") == "00"], "%Y-%m-%d")
  raw <- data.frame(Date = ts, MET_tmpair = rnorm(n, 19), MET_pprain = 0)
  o <- prepare_obs_met(raw, datetime_col = "Date", tz = TZ, resample = "none",
                       verbose = FALSE)
  expect_equal(nrow(o), n)
  expect_equal(attr(o, "resolution"), "hourly")
  expect_equal(as.numeric(diff(o$Date[1:2]), units = "hours"), 1)
})

test_that("prepare_obs_met parses several timestamp formats and date_format", {
  n <- 48
  t <- seq(as.POSIXct("2022-02-21 00:00", tz = TZ), by = "hour", length.out = n)
  for (f in c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%d/%m/%Y %H:%M",
              "%Y-%m-%dT%H:%M:%S")) {
    raw <- data.frame(Date = format(t, f), MET_tmpair = rnorm(n), MET_pprain = 0)
    o <- prepare_obs_met(raw, datetime_col = "Date", tz = TZ, resample = "none",
                         verbose = FALSE)
    expect_equal(attr(o, "resolution"), "hourly", label = f)
    expect_equal(nrow(o), n, label = f)
  }
  raw <- data.frame(Date = format(t, "%Y%m%d %H:%M:%S"), MET_tmpair = 1, MET_pprain = 0)
  o <- prepare_obs_met(raw, datetime_col = "Date", tz = TZ, resample = "none",
                       date_format = "%Y%m%d %H:%M:%S", verbose = FALSE)
  expect_equal(nrow(o), n)
})

test_that("prepare_obs_met honours the hour-labelling convention", {
  t <- seq(as.POSIXct("2024-01-01 00:00", tz = TZ), by = "15 min",
           length.out = 4 * 24)
  raw <- data.frame(timestamp = t, MET_pprain = 0.05, MET_tmpair = 15)
  beg <- prepare_obs_met(raw, tz = TZ, resample = "hour",
                         interval = "beginning", verbose = FALSE)
  expect_equal(as.integer(format(beg$Date[1], "%H", tz = TZ)), 0L)
  expect_equal(beg$MET_pprain[1], 0.20, tolerance = 1e-8)
  end <- prepare_obs_met(raw, tz = TZ, resample = "hour",
                         interval = "ending", verbose = FALSE)
  expect_equal(as.integer(format(end$Date[2], "%H", tz = TZ)), 1L)
  ## no records are lost either way
  expect_equal(sum(beg$MET_pprain), sum(end$MET_pprain), tolerance = 1e-8)
})

test_that("met_to_daily aggregates with rain summed and means elsewhere", {
  h <- data.frame(Date = seq(as.POSIXct("2024-01-01", tz = TZ), by = "hour",
                             length.out = 48),
                  MET_tmpair = rep(c(10, 20), each = 24),
                  MET_pprain = 0.5)
  d <- met_to_daily(h, tz = TZ)
  expect_s3_class(d$Date, "Date")
  expect_equal(nrow(d), 2)
  expect_equal(d$MET_tmpair, c(10, 20))
  expect_equal(d$MET_pprain, c(12, 12))
})
