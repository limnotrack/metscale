test_that("download_era5_isimip_point() returns an AEME data frame", {
  skip_on_cran()
  skip_if_offline()
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("terra")

  lon <- 175.27
  lat <- -37.80
  vars <- c("MET_tmpair", "MET_humrel", "MET_pprain", "MET_radswd", "MET_wndspd")

  met <- download_era5_isimip_point(lon = lon, lat = lat, years = 2021,
                                    vars = vars)

  expect_s3_class(met, "data.frame")
  expect_true("Date" %in% names(met))
  expect_true(any(grepl("^MET_", names(met))))
  expect_identical(ncol(met), length(vars) + 1L)
})

test_that("download_era5_cds() + read_era5_grib_point() round-trip", {
  skip("requires a Copernicus (CDS) key")

  lat <- -38.07782
  lon <- 176.2673
  ecmwfr::wf_set_key(key = Sys.getenv("CDS_KEY"), user = Sys.getenv("CDS_USER"))
  files <- download_era5_cds(lat = lat, lon = lon, year = 2024, month = 1,
                             variable = "2m_temperature",
                             path = file.path(tempdir(), "era5"),
                             user = Sys.getenv("CDS_USER"))
  df <- read_era5_grib_point(file = files, lat = lat, lon = lon)
  expect_s3_class(df, "data.frame")
  expect_true(all(!is.na(df$value)))
})

test_that("acquisition functions error clearly without their suggested deps", {
  # Only meaningful when the suggested package is absent.
  if (!requireNamespace("ecmwfr", quietly = TRUE)) {
    expect_error(download_era5_cds(lat = 0, lon = 0), "ecmwfr")
  }
  if (!requireNamespace("terra", quietly = TRUE)) {
    expect_error(read_era5_grib_point("x.grib", lat = 0, lon = 0), "terra")
  }
  if (!requireNamespace("httr2", quietly = TRUE)) {
    expect_error(download_era5_isimip_point(0, 0, 2021), "httr2")
  }
  if (!requireNamespace("stars", quietly = TRUE)) {
    expect_error(convert_era5_netcdf(lat = 0, lon = 0), "stars")
  }
  succeed()
})

test_that("check_vars() maps and validates variable names", {
  expect_identical(check_vars(c("MET_tmpair", "MET_pprain")), c("tas", "pr"))
  expect_identical(check_vars(c("tas", "pr")), c("tas", "pr"))
  expect_error(check_vars(c("MET_tmpair", "pr")), "Mixing")
  expect_error(check_vars("not_a_var"), "Invalid")
})
