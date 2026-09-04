## ===========================================================================
## Full climate-scenario meteorology batch for Lake Rotorua
## ---------------------------------------------------------------------------
## The narrated, precomputed version of this pipeline is
## vignette("scenario-workflow"). THIS script is the operational batch: it runs
## on the *full* (non-bundled) source data and writes the complete
## 4-SSP x 2-window matrix of daily + hourly CSVs to data-raw/output/.
##
## Point METSCALE_RAW_DATA at a directory holding:
##   rotorua_era5_hourly_met_full.csv     hourly ERA5-Land
##   rotorua_buoy_met_aeme_hr_full.csv    hourly Rotorua buoy
##   rotorua_cmip6_full/                  the NIWA CCAM/CMIP6 daily .nc
##
##   Rscript data-raw/scenario_batch_rotorua.R
##
## Order matters: a reanalysis->observation correction is an absolute-level
## correction and must not be folded into a delta (see ?scenario_workflow) -
## correct the baseline first, apply the delta second.
## ===========================================================================

suppressWarnings(suppressMessages({
  devtools::load_all(".", quiet = TRUE)
}))

src     <- Sys.getenv("METSCALE_RAW_DATA", "~/data/metscale-raw")
out_dir <- "data-raw/output"
stopifnot(dir.exists(src))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

TZ   <- "Etc/GMT-12"
LON  <- 176.2717
LAT  <- -38.0790
ELEV <- 279

ref_period     <- 1995:2014
future_windows <- list("2040-2059" = 2040:2059, "2080-2099" = 2080:2099)
scenarios      <- c("ssp126", "ssp245", "ssp370", "ssp585")
## disaggregate this slice per scenario/window (must be populated in the ERA5
## baseline); widen once a gap-free ERA5 record is supplied.
disagg_years   <- 2023:2025

KIND <- c(MET_tmpair = "add",   MET_radswd = "add",
          MET_pprain = "ratio", MET_wndspd = "ratio", MET_humrel = "ratio")

## ===========================================================================
## 1. Bias-correct hourly ERA5 against the buoy
## ===========================================================================
message("\n== 1. ERA5 bias correction ==")
obs <- prepare_obs_met(file.path(src, "rotorua_buoy_met_aeme_hr_full.csv"),
                       resample = "hour", tz = TZ, station = "rotorua_buoy",
                       verbose = FALSE)
era5 <- utils::read.csv(file.path(src, "rotorua_era5_hourly_met_full.csv"),
                        check.names = FALSE)
era5$Date <- as.POSIXct(era5$Date, tz = TZ, format = "%Y-%m-%d %H:%M:%S")
era5 <- era5[!is.na(era5$Date), ]
attr(era5, "tz") <- TZ; attr(era5, "lat") <- LAT; attr(era5, "lon") <- LON

bc <- fit_met_bias_correction(era5, obs, method = "scale", by = "doy-loess",
                              verbose = TRUE)
era5_corr <- apply_met_bias_correction(era5, bc, expand = TRUE, lat = LAT,
                                       lon = LON, elev = ELEV, tz = TZ,
                                       verbose = FALSE)

## ===========================================================================
## 2. Bias-corrected daily baseline
## ===========================================================================
message("\n== 2. Corrected daily baseline ==")
baseline_daily <- bias_correct_daily_baseline(era5, bc, lat = LAT, lon = LON,
                                              elev = ELEV, tz = TZ,
                                              verbose = TRUE)
ok <- stats::complete.cases(
  baseline_daily[c("MET_radswd", "MET_tmpair", "MET_pprain", "MET_wndspd",
                   "MET_humrel")])
baseline_daily <- baseline_daily[ok, ]
message("  usable baseline: ", paste(range(as.integer(format(
  baseline_daily$Date, "%Y"))), collapse = "-"), "  (", nrow(baseline_daily),
  " days)")

## ===========================================================================
## 3. CMIP6 projections -> delta-change factors
## ===========================================================================
message("\n== 3. CMIP6 delta-change ==")
cmip <- extract_cmip6_point(file.path(src, "rotorua_cmip6_full"),
                            lon = LON, lat = LAT, vars = names(KIND),
                            verbose = FALSE)
cmip_by <- split(cmip, cmip$experiment)
message("  experiments: ", paste(names(cmip_by), collapse = ", "))

monthly_delta <- function(fut, hist, window_years) {
  mh <- as.integer(format(hist$Date, "%m")); hy <- as.integer(format(hist$Date, "%Y"))
  mf <- as.integer(format(fut$Date,  "%m")); fy <- as.integer(format(fut$Date,  "%Y"))
  kh <- hy %in% ref_period; kf <- fy %in% window_years
  lapply(names(KIND), function(v) {
    a <- tapply(hist[[v]][kh], mh[kh], mean, na.rm = TRUE)
    b <- tapply(fut[[v]][kf],  mf[kf], mean, na.rm = TRUE)
    d <- if (KIND[[v]] == "ratio") b / a else b - a
    stats::setNames(as.numeric(d[as.character(1:12)]), 1:12)
  }) |> stats::setNames(names(KIND))
}

apply_delta <- function(base, delta) {
  mo <- as.integer(format(base$Date, "%m"))
  out <- base
  for (v in names(delta)) {
    f <- delta[[v]][mo]
    out[[v]] <- if (KIND[[v]] == "ratio") out[[v]] * f else out[[v]] + f
  }
  out$MET_humrel <- pmin(pmax(out$MET_humrel, 0), 100)
  for (v in c("MET_radswd", "MET_wndspd", "MET_pprain"))
    out[[v]][is.finite(out[[v]]) & out[[v]] < 0] <- 0
  em <- expand_met(out[, c("Date", "MET_radswd", "MET_tmpair", "MET_pprain",
                           "MET_humrel", "MET_wndspd", "MET_prsttn")],
                   lat = LAT, lon = LON, elev = ELEV, tz = TZ)
  attr(em, "tz") <- TZ; attr(em, "lat") <- LAT; attr(em, "lon") <- LON
  em
}

## ===========================================================================
## 4. Projection + disaggregation, per scenario / window
## ===========================================================================
message("\n== 4. Projection + disaggregation ==")
summary_rows <- list()
for (scn in scenarios) {
  fut <- cmip_by[[scn]]
  if (is.null(fut)) { warning("no CMIP6 experiment ", scn); next }
  for (win in names(future_windows)) {
    tag   <- sprintf("%s_%s", scn, win)
    delta <- monthly_delta(fut, cmip_by$historical, future_windows[[win]])
    proj  <- apply_delta(baseline_daily, delta)

    dT <- mean(delta$MET_tmpair)
    dP <- (mean(delta$MET_pprain) - 1) * 100
    message(sprintf("  %-16s  dT = %+5.2f degC   dPrecip = %+5.1f %%",
                    tag, dT, dP))
    utils::write.csv(proj, file.path(out_dir, sprintf("rotorua_%s_daily.csv", tag)),
                     row.names = FALSE)

    slice  <- proj[as.integer(format(proj$Date, "%Y")) %in% disagg_years, ]
    hourly <- disaggregate_met_to_hourly(slice, donor = era5_corr,
                                         method = "fragments", swr = "clearsky",
                                         lat = LAT, lon = LON, elev = ELEV,
                                         tz = TZ, seed = 42, expand = TRUE,
                                         verbose = FALSE)
    utils::write.csv(
      data.frame(Date = format(hourly$Date, "%Y-%m-%d %H:%M:%S"),
                 hourly[setdiff(names(hourly), "Date")]),
      file.path(out_dir, sprintf("rotorua_%s_hourly.csv", tag)),
      row.names = FALSE)

    back <- met_to_daily(hourly, tz = TZ, min_frac = 1)
    m <- match(as.Date(back$Date), as.Date(slice$Date))
    summary_rows[[tag]] <- data.frame(
      scenario = scn, window = win, dT_degC = round(dT, 2),
      dPrecip_pct = round(dP, 1), hourly_rows = nrow(hourly),
      tmpair_daily_err = signif(max(abs(back$MET_tmpair - slice$MET_tmpair[m])), 3))
  }
}

## reference: disaggregate the unshifted corrected baseline
base_slice <- baseline_daily[as.integer(format(baseline_daily$Date, "%Y")) %in%
                               disagg_years, ]
base_hourly <- disaggregate_met_to_hourly(base_slice, donor = era5_corr,
                                          method = "fragments", swr = "clearsky",
                                          lat = LAT, lon = LON, elev = ELEV,
                                          tz = TZ, seed = 42, expand = TRUE,
                                          verbose = FALSE)
utils::write.csv(
  data.frame(Date = format(base_hourly$Date, "%Y-%m-%d %H:%M:%S"),
             base_hourly[setdiff(names(base_hourly), "Date")]),
  file.path(out_dir, "rotorua_baseline_hourly.csv"), row.names = FALSE)

## ===========================================================================
## 5. Summary
## ===========================================================================
message("\n== 5. Summary ==")
summ <- do.call(rbind, summary_rows); rownames(summ) <- NULL
print(summ)
cat("\nOutputs in ", normalizePath(out_dir), "\n", sep = "")
