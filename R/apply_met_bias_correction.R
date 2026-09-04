#' Apply a fitted ERA5 met bias correction to a full record
#'
#' Takes the object from [fit_met_bias_correction()] and applies it to any
#' ERA5 met frame from [extract_era5_hourly_met()] /
#' [extract_era5_lake_met()] - typically the full record, not just the
#' training window. Each corrected variable is clamped back to physical
#' bounds. Optionally the corrected primaries are expanded so the
#' dependent variables (dew point, vapour pressure, cloud cover, longwave,
#' u/v wind, station pressure) are regenerated consistently with
#' [expand_met()].
#'
#' @param era5 data frame with `Date` + `MET_*` columns.
#' @param bc a `met_biascorr` object from [fit_met_bias_correction()].
#' @param vars subset of `names(bc$models)` to apply; default all.
#' @param clamp clamp to physical bounds after correcting (default `TRUE`):
#'   `MET_pprain`/`MET_ppsnow`/`MET_radswd`/`MET_radlwd`/`MET_wndspd` >= 0,
#'   `MET_humrel` within 0 to 100, `MET_radswd` <= `swr_ceiling`.
#' @param swr_ceiling hard upper bound for corrected `MET_radswd` (W/m2).
#'   Default 1361 (solar constant); pass a clear-sky series (same length as
#'   `era5`) for a tighter, time-varying cap.
#' @param expand if `TRUE`, keep `Date` + corrected primaries and call
#'   [expand_met()] to rebuild the full set. Needs `lat`/`lon`/`elev`
#'   (taken from `attr(era5, "lat")` / `"lon"` when `NULL`).
#' @param lat,lon,elev lake position for `expand`.
#' @param tz timezone for the solar geometry in [expand_met()]; defaults to
#'   the `tz` attribute of `era5`, else `"Etc/GMT-12"`.
#' @param verbose report which variables were corrected.
#'
#' @return `era5` with corrected columns (same class/attributes), plus
#'   `attr(., "biascorr")` recording the training window and methods. When
#'   `expand = TRUE`, the [expand_met()] output frame.
#'
#' @seealso [fit_met_bias_correction()], [met_to_daily()], [expand_met()]
#' @export
apply_met_bias_correction <- function(era5, bc,
                                      vars = NULL,
                                      clamp = TRUE,
                                      swr_ceiling = 1361,
                                      expand = FALSE,
                                      lat = NULL, lon = NULL, elev = NULL,
                                      tz = NULL,
                                      verbose = TRUE) {

  stopifnot(inherits(bc, "met_biascorr"), is.data.frame(era5), "Date" %in% names(era5))
  say <- function(...) if (isTRUE(verbose)) message(...)
  vars <- if (is.null(vars)) names(bc$models) else intersect(vars, names(bc$models))
  vars <- intersect(vars, names(era5))
  if (!length(vars)) stop("None of the corrected variables are in 'era5'.")

  d   <- as.POSIXct(era5$Date)
  mon <- as.integer(format(d, "%m"))
  doy <- as.integer(format(d, "%j"))

  out <- era5
  for (v in vars) {
    out[[v]] <- .mbc_predict(bc$models[[v]], era5[[v]], mon, doy)
    say("  corrected ", v)
  }

  if (isTRUE(clamp)) {
    nn <- intersect(c("MET_pprain", "MET_ppsnow", "MET_radswd",
                      "MET_radlwd", "MET_wndspd"), vars)
    for (v in nn) out[[v]][is.finite(out[[v]]) & out[[v]] < 0] <- 0
    if ("MET_humrel" %in% vars)
      out$MET_humrel <- pmin(pmax(out$MET_humrel, 0), 100)
    if ("MET_radswd" %in% vars) {
      ceil <- if (length(swr_ceiling) == nrow(out)) swr_ceiling else swr_ceiling[1]
      out$MET_radswd <- pmin(out$MET_radswd, ceil)
    }
  }

  attr(out, "biascorr") <- list(trained = c(format(bc$training$start),
                                            format(bc$training$end)),
                                station = bc$training$station,
                                methods = vapply(bc$models[vars],
                                                 `[[`, character(1), "method"))

  if (!isTRUE(expand)) return(out)

  ## ---- regenerate the dependent variables ---------------------------
  lat  <- lat  %||% attr(era5, "lat")
  lon  <- lon  %||% attr(era5, "lon")
  tz   <- tz   %||% attr(era5, "tz") %||% "Etc/GMT-12"
  if (is.null(lat) || is.null(lon))
    stop("expand = TRUE needs 'lat'/'lon' (not found as attributes of 'era5').")
  if (is.null(elev)) { elev <- 0; say("elev not supplied - using 0 m for expand_met()") }

  ## MET_radlwd / MET_prsttn kept when present so a correction you fitted
  ## against observations survives; expand_met() only regenerates the ones
  ## that are absent.
  prim <- c("MET_radswd", "MET_tmpair", "MET_pprain", "MET_ppsnow",
            "MET_tmpdew", "MET_humrel", "MET_wndspd", "MET_wnddir",
            "MET_prsttn", "MET_radlwd")
  keep <- c("Date", intersect(prim, names(out)))
  sub  <- out[, keep, drop = FALSE]
  need <- intersect(c("MET_radswd", "MET_tmpair", "MET_pprain"), names(sub))
  ok   <- stats::complete.cases(sub[, need, drop = FALSE])
  if (any(!ok)) say("expand_met(): dropping ", sum(!ok),
                    " row(s) with missing radswd/tmpair/pprain")
  em <- expand_met(sub[ok, , drop = FALSE], lat = lat, lon = lon,
                   elev = elev, tz = tz)
  attr(em, "biascorr") <- attr(out, "biascorr")
  for (a in c("lat", "lon", "tz", "method", "lake_id", "lake_name"))
    if (!is.null(attr(era5, a))) attr(em, a) <- attr(era5, a)
  em
}

#' Aggregate a (sub-)hourly met frame to daily
#'
#' Rain/snow are summed, everything else averaged; `Date` is returned as
#' class `Date`, which is what lake-model builders such as
#' `AEME::build_aeme()` expect.
#'
#' @param met data frame with `Date` (POSIXct) + `MET_*` columns.
#' @param tz time zone used to assign calendar days (default: the `tz`
#'   attribute of `met`, else `"Etc/GMT-12"`).
#' @param min_frac drop days with less than this fraction of expected
#'   hourly records (default 0.5); set 0 to keep all.
#' @return daily data frame, `Date` first.
#' @examples
#' h <- data.frame(Date = seq(as.POSIXct("2024-01-01", tz = "Etc/GMT-12"),
#'                            by = "hour", length.out = 48),
#'                 MET_tmpair = rnorm(48, 15), MET_pprain = 0.1)
#' met_to_daily(h)
#' @export
met_to_daily <- function(met, tz = NULL, min_frac = 0.5) {
  stopifnot(is.data.frame(met), "Date" %in% names(met))
  if (inherits(met$Date, "Date")) return(met)
  tz <- tz %||% attr(met, "tz") %||% "Etc/GMT-12"
  day <- as.Date(as.POSIXct(met$Date), tz = tz)
  vcols <- setdiff(names(met), "Date")
  sum_v <- intersect(c("MET_pprain", "MET_ppsnow"), vcols)
  g <- split(seq_len(nrow(met)), day)
  step_h <- stats::median(as.numeric(diff(as.POSIXct(met$Date)), units = "hours"), na.rm = TRUE)
  exp_n <- if (is.finite(step_h) && step_h > 0) 24 / step_h else 1
  rows <- lapply(names(g), function(k) {
    ix <- g[[k]]
    if (length(ix) < min_frac * exp_n) return(NULL)
    vals <- lapply(vcols, function(v) {
      x <- met[[v]][ix]
      if (all(is.na(x))) NA_real_
      else if (v %in% sum_v) sum(x, na.rm = TRUE)
      else mean(x, na.rm = TRUE)
    })
    data.frame(Date = as.Date(k), stats::setNames(as.data.frame(vals), vcols))
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  for (a in c("lat", "lon", "tz", "lake_id", "lake_name", "biascorr"))
    if (!is.null(attr(met, a))) attr(out, a) <- attr(met, a)
  out
}
