hourly_met <- function(n = 12) {
  data.frame(
    Date = seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = n),
    site = "A",
    MET_tmpair = seq(10, 15, length.out = n),
    MET_tmpdew = seq(6, 9, length.out = n),
    MET_humrel = seq(70, 90, length.out = n),
    MET_prsttn = 98000 + 0:(n - 1),
    MET_prvapr = seq(8, 12, length.out = n),          # hPa
    MET_wndspd = seq(2, 6, length.out = n),
    MET_wnddir = seq(0, 330, length.out = n),
    MET_radswd = seq(0, 800, length.out = n),
    MET_cldcvr = seq(0, 1, length.out = n),           # fraction
    MET_pprain = rep(c(0, 1.2), length.out = n))      # mm/hour
}

test_that("met_to_cf renames and converts units", {
  out <- met_to_cf(hourly_met())

  expect_true(all(c("time", "tas", "tdps", "hurs", "ps", "pvap", "sfcWind",
                    "sfcWindDir", "rsds", "clt", "pr") %in% names(out)))
  expect_false(any(grepl("^MET_", names(out))))
  expect_identical(names(out)[1], "time")

  m <- hourly_met()
  expect_equal(out$tas, m$MET_tmpair + 273.15)
  expect_equal(out$pvap, m$MET_prvapr * 100)          # hPa -> Pa
  expect_equal(out$clt, m$MET_cldcvr * 100)           # fraction -> %
  expect_equal(out$pr, m$MET_pprain / 3600)           # mm/hr -> kg m-2 s-1
  expect_equal(out$sfcWind, m$MET_wndspd)             # unchanged
  expect_equal(out$ps, m$MET_prsttn)                  # unchanged

  expect_equal(attr(out, "timestep_s"), 3600)
  expect_equal(attr(out, "cf_units")[["tas"]], "K")
  expect_equal(attr(out, "cf_standard_names")[["pr"]], "precipitation_flux")
})

test_that("non-MET columns are carried through unchanged", {
  out <- met_to_cf(hourly_met())
  expect_identical(out$site, rep("A", 12))
})

test_that("met_to_cf / cf_to_met round-trip", {
  m <- hourly_met()
  rt <- cf_to_met(met_to_cf(m))
  for (v in setdiff(names(m), c("Date", "site")))
    expect_equal(rt[[v]], m[[v]], tolerance = 1e-9, label = v)
  expect_identical(names(rt)[1], "Date")
  expect_equal(as.numeric(rt$Date), as.numeric(m$Date))
})

test_that("explicit timestep overrides inference", {
  out <- met_to_cf(hourly_met(), timestep = 1800)
  expect_equal(attr(out, "timestep_s"), 1800)
  expect_equal(out$pr, hourly_met()$MET_pprain / 1800)
})

test_that("daily Date gives an 86400 s timestep", {
  d <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 6),
                  MET_tmpair = 12, MET_pprain = c(0, 5, 0, 10, 2, 0))
  out <- met_to_cf(d)
  expect_equal(attr(out, "timestep_s"), 86400)
  expect_equal(out$pr, d$MET_pprain / 86400)
})

test_that("single row + precipitation needs an explicit timestep", {
  one <- data.frame(Date = as.POSIXct("2024-01-01", tz = "UTC"),
                    MET_tmpair = 10, MET_pprain = 0.5)
  expect_error(met_to_cf(one), "timestep")
  expect_silent(out <- met_to_cf(one, timestep = 3600))
  expect_equal(out$pr, 0.5 / 3600)
})

test_that("vars filter restricts the conversion", {
  out <- met_to_cf(hourly_met(), vars = c("MET_tmpair", "MET_wndspd"))
  expect_true(all(c("tas", "sfcWind") %in% names(out)))
  expect_true("MET_humrel" %in% names(out))           # untouched, still MET_*
  expect_false("hurs" %in% names(out))
})

test_that("reads a csv path and writes outfile", {
  m <- hourly_met()
  fin <- tempfile(fileext = ".csv"); fout <- tempfile(fileext = ".csv")
  on.exit(unlink(c(fin, fout)))
  utils::write.csv(m, fin, row.names = FALSE)

  res <- met_to_cf(fin, outfile = fout)
  expect_true(file.exists(fout))
  back <- utils::read.csv(fout, check.names = FALSE)
  expect_true(all(c("time", "tas", "pr") %in% names(back)))
  expect_equal(back$tas, m$MET_tmpair + 273.15, tolerance = 1e-6)
})
