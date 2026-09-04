TZ <- "Etc/GMT-12"; LAT <- -38.079; LON <- 176.2717

daily_met <- function(n = 30) {
  data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = n),
             MET_radswd = seq(80, 320, length.out = n),
             MET_tmpair = 15 + sin(seq_len(n)),
             MET_humrel = 70,
             MET_wndspd = 4,
             MET_pprain = rep(c(0, 5), length.out = n))
}

test_that("expand_met fills the full variable set with no NAs", {
  em <- expand_met(daily_met(), lat = LAT, lon = LON, elev = 280, tz = TZ)
  expect_setequal(names(em), c("Date", met_vars()$name))
  expect_equal(nrow(em), 30)
  expect_false(anyNA(em))
})

test_that("expand_met keeps supplied variables and returns pressure in Pa", {
  m <- daily_met()
  m$MET_prsttn <- 97300
  em <- expand_met(m, lat = LAT, lon = LON, elev = 280, tz = TZ)
  expect_equal(em$MET_prsttn, rep(97300, 30))
  ## when not supplied, it is derived - and still in Pa
  em2 <- expand_met(daily_met(), lat = LAT, lon = LON, elev = 280, tz = TZ)
  expect_true(all(em2$MET_prsttn > 90000 & em2$MET_prsttn < 101325))
  expect_true(all(em2$MET_prmslp > 95000 & em2$MET_prmslp < 108000))
})

test_that("expand_met works at hourly resolution without resampling", {
  hr <- data.frame(
    Date = seq(as.POSIXct("2024-01-01", tz = TZ), by = "hour", length.out = 240),
    MET_radswd = pmax(0, 500 * sin(seq(0, 10 * pi, length.out = 240))),
    MET_tmpair = 15, MET_humrel = 70, MET_wndspd = 4, MET_pprain = 0)
  em <- expand_met(hr, lat = LAT, lon = LON, elev = 280, tz = TZ)
  expect_equal(nrow(em), 240)
  expect_equal(em$Date, hr$Date)
  expect_false(anyNA(em))
})

test_that("expand_met errors clearly on missing requirements", {
  m <- daily_met(); m$MET_radswd <- NULL
  expect_error(expand_met(m, LAT, LON, 280), "MET_radswd")
  m2 <- daily_met(); m2$MET_humrel <- NULL
  expect_error(expand_met(m2, LAT, LON, 280), "MET_humrel|MET_tmpdew")
  m3 <- daily_met(); m3$MET_wndspd <- NULL
  expect_error(expand_met(m3, LAT, LON, 280), "wind")
})

test_that("calc_cc returns a bounded fraction, cloudier on dull days", {
  m <- daily_met()
  cc <- calc_cc(m$Date, airt = m$MET_tmpair, swr = m$MET_radswd, relh = 70,
                lat = LAT, lon = LON, elev = 280, tz = TZ)
  expect_length(cc, nrow(m))
  expect_true(all(cc >= 0 & cc <= 1))
  expect_gt(cc[which.min(m$MET_radswd)], cc[which.max(m$MET_radswd)])
  expect_silent(calc_cc(m$Date, airt = 18, swr = m$MET_radswd, relh = 70,
                        lat = LAT, lon = LON, elev = 280, tz = TZ))
})

test_that("guess_met_vars matches common naming conventions", {
  expect_equal(guess_met_vars(c("AirTemp_C", "WindSpd", "SolarRad", "Rain_mm",
                                "RH", "Pressure_hPa", "dewpt", "junk")),
               c("MET_tmpair", "MET_wndspd", "MET_radswd", "MET_pprain",
                 "MET_humrel", "MET_prsttn", "MET_tmpdew", NA))
  ## ERA5 / CMIP short names
  expect_equal(guess_met_vars(c("t2m", "d2m", "u10", "v10", "ssrd", "strd", "tp", "sf", "sp")),
               c("MET_tmpair", "MET_tmpdew", "MET_wnduvu", "MET_wnduvv",
                 "MET_radswd", "MET_radlwd", "MET_pprain", "MET_ppsnow",
                 "MET_prsttn"))
  ## standard names pass through untouched
  expect_equal(guess_met_vars(met_vars()$name), met_vars()$name)
})

test_that("standardise_met renames and fixes units", {
  raw <- data.frame(timestamp = as.Date("2024-01-01") + 0:4,
                    AirTemp_K   = c(291, 289, 292, 288, 293),
                    WindSpd_kmh = c(40, 65, 25, 79, 40),
                    SolarRad    = c(300, 120, 280, 90, 310),
                    Rain_mm     = c(0, 12, 0, 25, 0),
                    RH          = c(0.7, 0.85, 0.65, 0.9, 0.6),
                    Press_hPa   = c(1012, 1008, 1015, 1002, 1018))
  out <- suppressMessages(standardise_met(raw, verbose = FALSE))
  expect_true(all(c("Date", "MET_tmpair", "MET_wndspd", "MET_radswd",
                    "MET_pprain", "MET_humrel", "MET_prsttn") %in% names(out)))
  expect_equal(out$MET_tmpair, c(291, 289, 292, 288, 293) - 273.15)
  expect_equal(out$MET_wndspd, c(40, 65, 25, 79, 40) / 3.6)
  expect_equal(out$MET_humrel, c(70, 85, 65, 90, 60))
  expect_equal(out$MET_prsttn, c(1012, 1008, 1015, 1002, 1018) * 100)
})

test_that("standardise_met warns when required variables are missing", {
  raw <- data.frame(Date = as.Date("2024-01-01") + 0:2, AirTemp = c(15, 16, 17))
  expect_warning(standardise_met(raw, verbose = FALSE), "absent after renaming")
})
