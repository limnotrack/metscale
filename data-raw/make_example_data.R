## ===========================================================================
## Regenerate the slim example fixtures in inst/extdata/ from the full source
## data (which is NOT in the repo).
##
## Point CLIMPREP_RAW_DATA at a directory holding:
##   rotorua_era5_hourly_met_full.csv     (hourly ERA5-Land, 1968-2025)
##   rotorua_buoy_met_aeme_hr_full.csv    (hourly Rotorua buoy, 2022-2026)
##   rotorua_cmip6_full/                  (25 NIWA CCAM/CMIP6 daily .nc)
## Maintainer copy: LimnoTrack shared storage (ask Tadhg).
##
##   Rscript data-raw/make_example_data.R
##
## Produces (~3.5 MB total, from ~199 MB):
##   inst/extdata/rotorua_era5_hourly_met.csv.gz
##   inst/extdata/rotorua_buoy_met_aeme_hr.csv.gz
##   inst/extdata/rotorua_cmip6/  (15 cropped .nc: historical + ssp245 + ssp585)
## rotorua_lake_shape.rds is left untouched.
## ===========================================================================

suppressWarnings(suppressMessages({
  devtools::load_all(".", quiet = TRUE)   # for climprep:::.cmip6_time_to_date + extract_cmip6_point
  library(ncdf4)
}))

src     <- Sys.getenv("CLIMPREP_RAW_DATA", "~/data/climprep-raw")
out_ex  <- "inst/extdata"
out_nc  <- file.path(out_ex, "rotorua_cmip6")
stopifnot(dir.exists(src))
dir.create(out_nc, showWarnings = FALSE, recursive = TRUE)

LON <- 176.2717
LAT <- -38.0790
DEMO_YEARS  <- 2023:2025
## Reference / future windows are shortened to 10 years for the *bundled*
## example (keeps inst/extdata small). Production delta-change uses 20-year
## windows (e.g. 1995-2014 vs 2080-2099); the mechanics are identical.
REF_PERIOD  <- 2005:2014
FUT_WINDOW  <- 2090:2099
EXPERIMENTS <- c("historical", "ssp245", "ssp585")     # add ssp126/ssp370 for the full set
VARS        <- c("hurs", "pr", "rsds", "sfcWind", "tas")
GRID_HALF   <- 1L                                       # 1 -> 3x3 window

## rounding: enough precision for the science, not the 15-17 stored digits
round_cols <- function(df) {
  dp <- c(MET_tmpair = 3, MET_tmpdew = 3, MET_radswd = 2, MET_radlwd = 2,
          MET_pprain = 4, MET_ppsnow = 4, MET_wnduvu = 3, MET_wnduvv = 3,
          MET_wndspd = 3, MET_wnddir = 1, MET_humrel = 2, MET_prsttn = 1)
  for (v in intersect(names(dp), names(df)))
    df[[v]] <- round(df[[v]], dp[[v]])
  df
}
write_gz <- function(df, path) {
  con <- gzfile(path, "w", compression = 9); on.exit(close(con))
  utils::write.csv(df, con, row.names = FALSE)
  invisible(path)
}

## ---- 1. ERA5 hourly CSV ---------------------------------------------------
message("ERA5 hourly CSV ...")
e <- utils::read.csv(file.path(src, "rotorua_era5_hourly_met_full.csv"),
                     check.names = FALSE, stringsAsFactors = FALSE)
e$Date <- as.POSIXct(e$Date, tz = "Etc/GMT-12", format = "%Y-%m-%d %H:%M:%S")
met    <- grep("^MET_", names(e), value = TRUE)
keep   <- rowSums(!is.na(e[met])) > 0 &
          as.integer(format(e$Date, "%Y")) %in% DEMO_YEARS
e <- e[keep, , drop = FALSE]
e$Date <- format(e$Date, "%Y-%m-%d %H:%M:%S")
e <- round_cols(e)
write_gz(e, file.path(out_ex, "rotorua_era5_hourly_met.csv.gz"))
message("  ", nrow(e), " rows")

## ---- 2. buoy hourly CSV -------------------------------------------------
message("buoy hourly CSV ...")
b <- utils::read.csv(file.path(src, "rotorua_buoy_met_aeme_hr_full.csv"),
                     check.names = FALSE, stringsAsFactors = FALSE)
b <- b[, setdiff(names(b), c("", "MET_wnddir_Rbar")), drop = FALSE]  # drop row-index + circular-stats helper
b$Date <- as.POSIXct(b$Date, tz = "Etc/GMT-12", format = "%Y-%m-%d %H:%M:%S")
b <- b[as.integer(format(b$Date, "%Y")) %in% DEMO_YEARS, , drop = FALSE]
b$Date <- format(b$Date, "%Y-%m-%d %H:%M:%S")
b <- round_cols(b)
write_gz(b, file.path(out_ex, "rotorua_buoy_met_aeme_hr.csv.gz"))
message("  ", nrow(b), " rows")

## ---- 3. crop the CMIP6 netCDFs ---------------------------------------------
crop_one <- function(fin, fout, years) {
   nc <- nc_open(fin); on.exit(nc_close(nc))
  vn  <- names(nc$var)[1]
  lon <- as.numeric(nc$dim$longitude$vals)
  lat <- as.numeric(nc$dim$latitude$vals)
  tv  <- as.numeric(ncvar_get(nc, "time"))
  tu  <- ncatt_get(nc, "time", "units")$value
  cal <- ncatt_get(nc, "time", "calendar")$value

  ix0 <- which.min(abs(lon - LON)); iy0 <- which.min(abs(lat - LAT))
  ix  <- pmin(pmax(ix0 + (-GRID_HALF:GRID_HALF), 1L), length(lon))
  iy  <- pmin(pmax(iy0 + (-GRID_HALF:GRID_HALF), 1L), length(lat))
  ix  <- unique(ix); iy <- unique(iy)

  dts <- climprep:::.cmip6_time_to_date(tv, tu, cal)
  it  <- which(as.integer(format(dts, "%Y")) %in% years)
  if (!length(it)) stop("no time steps in ", paste(range(years), collapse = "-"),
                        " for ", basename(fin))
  it <- seq(min(it), max(it))                            # contiguous slice

  arr <- ncvar_get(nc, vn,
                   start = c(ix[1], iy[1], it[1]),
                   count = c(length(ix), length(iy), length(it)),
                   collapse_degen = FALSE)
  fill <- ncatt_get(nc, vn, "_FillValue")
  fillv <- if (isTRUE(fill$hasatt)) fill$value else NA

  xd <- ncdim_def("longitude", nc$dim$longitude$units, lon[ix])
  yd <- ncdim_def("latitude",  nc$dim$latitude$units,  lat[iy])
  td <- ncdim_def("time", tu, tv[it], unlim = FALSE, calendar = cal)
  vu <- ncatt_get(nc, vn, "units")$value
  vd <- ncvar_def(vn, vu, list(xd, yd, td), missval = fillv,
                  prec = "float", compression = 5)
   out <- nc_create(fout, vd)
  ncvar_put(out, vd, arr)
  ln <- ncatt_get(nc, vn, "long_name")
  if (isTRUE(ln$hasatt)) ncatt_put(out, vn, "long_name", ln$value)
  nc_close(out)
  invisible(fout)
}

message("cropping CMIP6 netCDFs ...")
src_nc <- file.path(src, "rotorua_cmip6_full")
for (v in VARS) for (ex in EXPERIMENTS) {
  hit <- list.files(src_nc, pattern = sprintf("^%s_%s_.*\\.nc$", v, ex),
                    full.names = TRUE)
  if (!length(hit)) { warning("missing ", v, " / ", ex); next }
  years <- if (ex == "historical") REF_PERIOD else FUT_WINDOW
  crop_one(hit[1], file.path(out_nc, basename(hit[1])), years)
  message("  ", basename(hit[1]))
}

## ---- 4. regression gate: point series unchanged by the crop --------------
message("regression check (cropped vs full point series) ...")
pull <- function(dir) extract_cmip6_point(dir, lon = LON, lat = LAT,
                                          experiments = EXPERIMENTS,
                                          verbose = FALSE)
a <- pull(src_nc)
z <- pull(out_nc)
key <- c("Date", "experiment")
m <- merge(a, z, by = key, suffixes = c(".full", ".crop"))
vars_chk <- sub("\\.full$", "", grep("\\.full$", names(m), value = TRUE))
worst <- 0
for (v in vars_chk) {
  d <- abs(m[[paste0(v, ".full")]] - m[[paste0(v, ".crop")]])
  worst <- max(worst, max(d, na.rm = TRUE))
}
message(sprintf("  max abs diff = %.3g over %d shared rows", worst, nrow(m)))
if (worst > 1e-6) stop("crop changed the interpolated point series (", worst, ")")

## ---- 5. report ---------------------------------------------------------
sz <- function(p) sum(file.info(list.files(p, recursive = TRUE, full.names = TRUE))$size)
message(sprintf("\ninst/extdata now %.2f MB  (cmip6 %.2f MB)",
                sz(out_ex) / 1e6, sz(out_nc) / 1e6))
message("done.")
