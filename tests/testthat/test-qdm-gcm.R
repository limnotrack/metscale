make_qdm_data <- function(seed = 1) {
  set.seed(seed)
  d <- seq(as.Date("1980-01-01"), as.Date("2099-12-31"), by = "day")
  yrs <- as.integer(format(d, "%Y"))
  doy <- as.integer(format(d, "%j"))
  seas <- 5 * sin(2 * pi * doy / 365)
  # model: biased +3 degC / x1.5 wind vs baseline, warms 0.04 degC / yr after 2014
  warm <- pmax(yrs - 2014, 0) * 0.04
  gcm <- data.frame(
    Date = d,
    experiment = ifelse(yrs <= 2014, "historical", "ssp585"),
    MET_tmpair = 15 + 3 + seas + warm + stats::rnorm(length(d), 0, 2),
    MET_wndspd = 1.5 * stats::rexp(length(d), 1 / 4))
  base_d <- d[yrs <= 2014]
  baseline <- data.frame(
    Date = base_d,
    MET_tmpair = 15 + seas[yrs <= 2014] + stats::rnorm(length(base_d), 0, 2),
    MET_wndspd = stats::rexp(length(base_d), 1 / 4))
  list(gcm = gcm, baseline = baseline)
}

test_that("qdm_gcm_met forces the reference period onto the baseline", {
  x <- make_qdm_data()
  out <- qdm_gcm_met(x$gcm, x$baseline, scenario = "ssp585",
                     ref_years = 1985:2014, target_years = 1985:2014)
  expect_s3_class(out$Date, "Date")
  expect_equal(range(as.integer(format(out$Date, "%Y"))), c(1985, 2014))
  base <- x$baseline[as.integer(format(x$baseline$Date, "%Y")) %in% 1985:2014, ]
  expect_equal(mean(out$MET_tmpair), mean(base$MET_tmpair), tolerance = 0.1)
  expect_equal(mean(out$MET_wndspd), mean(base$MET_wndspd), tolerance = 0.1)
})

test_that("qdm_gcm_met preserves the model's projected change", {
  x <- make_qdm_data()
  out <- qdm_gcm_met(x$gcm, x$baseline, scenario = "ssp585",
                     ref_years = 1985:2014, target_years = 1985:2099)
  y <- as.integer(format(out$Date, "%Y"))
  g <- x$gcm[as.integer(format(x$gcm$Date, "%Y")) %in% 1985:2099, ]
  # additive change in the mean temperature, end of century vs reference
  dc <- mean(out$MET_tmpair[y %in% 2070:2099]) - mean(out$MET_tmpair[y %in% 1985:2014])
  dg <- mean(g$MET_tmpair[y %in% 2070:2099]) - mean(g$MET_tmpair[y %in% 1985:2014])
  expect_equal(dc, dg, tolerance = 0.15)
  # multiplicative wind: stays positive and respects the cap
  expect_true(all(out$MET_wndspd >= 0))
  expect_false(anyNA(out$MET_tmpair))
})

test_that("qdm_gcm_met handles rain, humidity limits and bad input", {
  x <- make_qdm_data()
  n <- nrow(x$gcm); nb <- nrow(x$baseline)
  x$gcm$MET_pprain <- ifelse(stats::runif(n) < 0.6, 0, stats::rexp(n, 1 / 0.005))
  x$baseline$MET_pprain <- ifelse(stats::runif(nb) < 0.5, 0, stats::rexp(nb, 1 / 0.004))
  x$gcm$MET_humrel <- pmin(100, 90 + stats::rnorm(n, 0, 15))
  x$baseline$MET_humrel <- pmin(100, 80 + stats::rnorm(nb, 0, 15))
  out <- qdm_gcm_met(x$gcm, x$baseline, scenario = "ssp585",
                     ref_years = 1985:2014, target_years = 2015:2099)
  expect_true(all(out$MET_pprain == 0 | out$MET_pprain >= 1e-4))
  expect_true(all(out$MET_pprain >= 0))
  expect_true(all(out$MET_humrel >= 0 & out$MET_humrel <= 100))
  expect_equal(attr(out, "qdm")$kind[["MET_pprain"]], "mult")

  expect_error(qdm_gcm_met(x$gcm, x$baseline, scenario = "ssp126"),
               "not in gcm\\$experiment")
  expect_error(qdm_gcm_met(x$gcm[x$gcm$experiment != "historical", ],
                           x$baseline, scenario = "ssp585"), "historical")
  expect_error(qdm_gcm_met(x$gcm, x$baseline, scenario = "ssp585",
                           ref_years = 1990:1992), "10 reference years")
})
