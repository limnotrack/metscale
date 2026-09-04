TZ <- "Etc/GMT-12"; LAT <- -38.079; LON <- 176.2717

## Synthetic hourly donor with a realistic diurnal cycle.
donor_hourly <- function(years = 2020:2022, seed = 21) {
  set.seed(seed)
  t <- seq(as.POSIXct(paste0(min(years), "-01-01 00:00"), tz = TZ),
           as.POSIXct(paste0(max(years), "-12-31 23:00"), tz = TZ), by = "hour")
  h <- as.integer(format(t, "%H", tz = TZ))
  d <- as.integer(format(t, "%j", tz = TZ))
  seas <- sin(2 * pi * (d - 300) / 365)
  wet <- rep(stats::rbinom(length(t) / 24 + 1, 1, 0.3), each = 24)[seq_along(t)]
  out <- data.frame(
    Date       = t,
    MET_tmpair = 13 + 6 * seas + 4 * sin((h - 9) / 24 * 2 * pi) + rnorm(length(t), 0, 1),
    MET_wndspd = pmax(0.05, 3.5 + 1.2 * sin((h - 12) / 24 * 2 * pi) + rnorm(length(t), 0, 0.7)),
    MET_humrel = pmin(100, pmax(5, 75 - 15 * sin((h - 9) / 24 * 2 * pi) + rnorm(length(t), 0, 5))),
    MET_radswd = pmax(0, (700 + 250 * seas) * pmax(0, sin((h - 6) / 12 * pi))),
    MET_pprain = wet * pmax(0, rnorm(length(t), 0.15, 0.3)))
  attr(out, "tz") <- TZ; attr(out, "lat") <- LAT; attr(out, "lon") <- LON
  out
}

test_that("disaggregation conserves daily means and rainfall totals", {
  donor <- donor_hourly()   # no u/v components -> MET_wndspd is shaped directly
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  for (meth in c("fragments", "diurnal")) {
    out <- disaggregate_met_to_hourly(daily, donor, method = meth,
                                      lat = LAT, lon = LON, tz = TZ,
                                      seed = 1, verbose = FALSE)
    expect_equal(nrow(out), nrow(daily) * 24)
    back <- met_to_daily(out, tz = TZ, min_frac = 1)
    for (v in c("MET_tmpair", "MET_wndspd", "MET_humrel", "MET_radswd",
                "MET_pprain"))
      expect_equal(back[[v]], daily[[v]], tolerance = 1e-6,
                   label = paste(meth, v))
  }
})

test_that("with u/v components, direction and speed come from the vector", {
  donor <- donor_hourly()
  uv <- ds2uv(runif(nrow(donor), 0, 360), donor$MET_wndspd)
  donor$MET_wnduvu <- uv[, "u"]; donor$MET_wnduvv <- uv[, "v"]
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  out <- suppressMessages(
    disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON, tz = TZ,
                               seed = 1, verbose = FALSE))
  ## u and v still conserve; speed is sqrt(u^2 + v^2), direction from atan2
  back <- met_to_daily(out, tz = TZ, min_frac = 1)
  expect_equal(back$MET_wnduvu, daily$MET_wnduvu, tolerance = 1e-6)
  expect_equal(back$MET_wnduvv, daily$MET_wnduvv, tolerance = 1e-6)
  expect_equal(out$MET_wndspd, sqrt(out$MET_wnduvu^2 + out$MET_wnduvv^2),
               tolerance = 1e-8)
  expect_true(all(out$MET_wnddir >= 0 & out$MET_wnddir < 360))
})

test_that("bounds are respected without breaking conservation", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  ## push humidity hard against the ceiling
  daily$MET_humrel <- pmin(100, daily$MET_humrel + 22)
  out <- disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON,
                                    tz = TZ, seed = 2, verbose = FALSE)
  expect_true(all(out$MET_humrel >= 0 & out$MET_humrel <= 100))
  expect_true(all(out$MET_wndspd >= 0))
  expect_true(all(out$MET_pprain >= 0))
  back <- met_to_daily(out, tz = TZ, min_frac = 1)
  expect_equal(back$MET_humrel, daily$MET_humrel, tolerance = 1e-6)
})

test_that("the diurnal cycle is reproduced far better than holding values flat", {
  donor <- donor_hourly()
  is22  <- format(donor$Date, "%Y") == "2022"
  truth <- donor[is22, ]
  pool  <- donor[!is22, ]
  daily <- met_to_daily(truth, tz = TZ, min_frac = 1)

  out  <- disaggregate_met_to_hourly(daily, pool, lat = LAT, lon = LON,
                                     tz = TZ, seed = 3, verbose = FALSE)
  flat <- truth
  flat[names(daily)[-1]] <- daily[rep(seq_len(nrow(daily)), each = 24), -1]

  h <- as.integer(format(truth$Date, "%H", tz = TZ))
  cyc <- function(x) tapply(x, h, mean)
  for (v in c("MET_tmpair", "MET_radswd", "MET_humrel")) {
    e_out  <- sqrt(mean((cyc(out[[v]])  - cyc(truth[[v]]))^2))
    e_flat <- sqrt(mean((cyc(flat[[v]]) - cyc(truth[[v]]))^2))
    expect_lt(e_out, e_flat / 2, label = paste("diurnal cycle error for", v))
  }
})

test_that("shortwave is dark at night and peaks around local noon", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  out <- disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON,
                                    tz = TZ, seed = 4, verbose = FALSE)
  h <- as.integer(format(out$Date, "%H", tz = TZ))
  expect_true(all(out$MET_radswd[h %in% c(0, 1, 2, 23)] == 0))
  expect_true(as.integer(names(which.max(tapply(out$MET_radswd, h, mean)))) %in% 11:14)
})

test_that("rainfall keeps intermittency and dry days stay dry", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  out <- disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON,
                                    tz = TZ, seed = 5, verbose = FALSE)
  by_day <- tapply(out$MET_pprain, as.Date(out$Date, tz = TZ), max)
  expect_true(all(by_day[daily$MET_pprain == 0] == 0))
  ## far fewer wet hours than spreading the daily total uniformly
  expect_lt(sum(out$MET_pprain > 0.001), sum(daily$MET_pprain > 0) * 24)
})

test_that("3-hourly output has the right shape and conserves totals", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  out <- disaggregate_met_to_hourly(daily, donor, timestep = "3hour",
                                    lat = LAT, lon = LON, tz = TZ,
                                    seed = 6, verbose = FALSE)
  expect_equal(nrow(out), nrow(daily) * 8)
  expect_equal(as.numeric(diff(out$Date[1:2]), units = "hours"), 3)
  back <- met_to_daily(out, tz = TZ, min_frac = 1)
  expect_equal(back$MET_tmpair, daily$MET_tmpair, tolerance = 1e-6)
  expect_equal(back$MET_pprain, daily$MET_pprain, tolerance = 1e-6)
})

test_that("variables absent from the donor are held constant", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  daily$MET_prsttn <- 97000 + seq_len(nrow(daily))
  out <- suppressMessages(
    disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON, tz = TZ,
                               seed = 7, verbose = FALSE))
  expect_equal(unique(round(diff(out$MET_prsttn[1:24]), 9)), 0)
  back <- met_to_daily(out, tz = TZ, min_frac = 1)
  expect_equal(back$MET_prsttn, daily$MET_prsttn, tolerance = 1e-8)
})

test_that("build_diurnal_climatology returns conservative shapes", {
  dc <- build_diurnal_climatology(donor_hourly())
  expect_s3_class(dc, "diurnal_climatology")
  expect_equal(dim(dc$shape$MET_tmpair), c(12L, 24L))
  expect_equal(rowMeans(dc$shape$MET_tmpair), rep(0, 12), tolerance = 1e-8)
  expect_equal(rowMeans(dc$shape$MET_wndspd), rep(1, 12), tolerance = 1e-8)
  expect_equal(rowSums(dc$shape$MET_pprain), rep(1, 12), tolerance = 1e-8)
  expect_output(print(dc), "diurnal_climatology")
})

test_that("expand = TRUE returns the full variable set", {
  donor <- donor_hourly()
  daily <- met_to_daily(donor[format(donor$Date, "%Y") == "2022", ],
                        tz = TZ, min_frac = 1)
  out <- disaggregate_met_to_hourly(daily, donor, lat = LAT, lon = LON,
                                    elev = 280, tz = TZ, expand = TRUE,
                                    seed = 8, verbose = FALSE)
  expect_setequal(names(out), c("Date", met_vars()$name))
  expect_false(anyNA(out))
})
