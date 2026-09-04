## ---------------------------------------------------------------------------
## Composing a local bias correction with a climate-scenario delta change.
## ---------------------------------------------------------------------------

#' Should a local bias correction be applied to climate scenario data?
#'
#' Not to the change factors themselves. A delta-change projection supplies
#' a *difference* (or ratio) between two model climates, in which the
#' systematic model bias largely cancels; a reanalysis-to-observation
#' correction is an *absolute level* correction and does not belong on a
#' delta. Correct the baseline instead, then apply the delta on top:
#'
#' \preformatted{
#' ERA5 hourly -> extract_era5_lake_met()
#'             -> fit_met_bias_correction(era5, obs)
#'             -> apply_met_bias_correction(full record)
#'             -> met_to_daily()                      # corrected baseline
#'             -> delta-change: extract_cmip6_point(), monthly change factors,
#'                add / multiply onto the baseline
#'             -> disaggregate_met_to_hourly()        # if sub-daily is needed
#' }
#'
#' See \code{vignette("scenario-workflow", package = "metscale")} for a
#' runnable end-to-end example on Lake Rotorua.
#'
#' Applying the local correction to the baseline *before* the delta-change
#' step is what makes the composition well defined, whatever kinds the two
#' adjustments are: the NIWA CCAM change fields are additive in degC for
#' temperature, percentage for rainfall, wind and humidity, and additive in
#' W m-2 for shortwave, while [fit_met_bias_correction()] picks the
#' transform per variable. Do not try to fold the local correction in
#' *after* the delta - correct first, shift second.
#'
#' A caveat worth carrying: both steps assume stationarity. A correction
#' fitted over a few years of observations is being asserted to hold under
#' a future climate. Prefer `method = "scale"` over quantile mapping for a
#' baseline that will be projected, since a fitted CDF extrapolates poorly
#' outside its training range.
#'
#' @name scenario_workflow
#' @seealso [bias_correct_daily_baseline()], [fit_met_bias_correction()],
#'   [extract_cmip6_point()], [disaggregate_met_to_hourly()]
NULL

#' Build a bias-corrected daily baseline for a climate-scenario workflow
#'
#' Applies a fitted [fit_met_bias_correction()] to a full hourly reanalysis
#' record, aggregates to daily and regenerates the dependent variables, so
#' the result is ready to be handed to a delta-change routine such as
#' `AEME`'s `climate_shift()` as the baseline meteorology.
#'
#' The rainfall column is always populated from the corrected record, so
#' that downstream code which special-cases an all-zero `MET_pprain` (as
#' `climate_shift()` does, by substituting inflow-derived rainfall) does
#' not take that branch unintentionally.
#'
#' @param era5 hourly reanalysis met, from [extract_era5_lake_met()].
#' @param bc a `met_biascorr` from [fit_met_bias_correction()]; `NULL` to
#'   aggregate without correcting.
#' @param lat,lon,elev lake position; taken from the attributes of `era5`
#'   when `NULL`.
#' @param tz timezone for day boundaries and solar geometry; defaults to
#'   the `tz` attribute of `era5`.
#' @param expand regenerate the dependent variables with [expand_met()]
#'   (default `TRUE`).
#' @param min_frac minimum fraction of a day that must be present for that
#'   day to be kept, passed to [met_to_daily()].
#' @param verbose print progress.
#'
#' @return daily data frame with `Date` of class `Date` and `MET_*`
#'   columns, carrying a `biascorr` attribute describing the correction.
#'
#' @seealso [scenario_workflow] for the full delta-change pipeline and
#'   \code{vignette("scenario-workflow", package = "metscale")}.
#'
#' @examples
#' \dontrun{
#' era5 <- extract_era5_lake_met("LID 11133", path = nc_dir, lakes = lakes,
#'                               method = "area", years = 1980:2024)
#' obs  <- prepare_obs_met("obs/rotorua_buoy_met.csv", resample = "hour")
#' bc   <- fit_met_bias_correction(era5, obs)
#'
#' baseline <- bias_correct_daily_baseline(era5, bc, elev = 279)
#'
#' ## hand to AEME's delta-change routine
#' inp <- AEME::input(aeme); inp$meteo <- baseline
#' AEME::input(aeme) <- inp
#' }
#' @export
bias_correct_daily_baseline <- function(era5, bc = NULL,
                                        lat = NULL, lon = NULL, elev = 0,
                                        tz = NULL, expand = TRUE,
                                        min_frac = 0.5, verbose = TRUE) {
  stopifnot(is.data.frame(era5), "Date" %in% names(era5))
  say <- function(...) if (isTRUE(verbose)) message(...)
  tz  <- tz  %||% attr(era5, "tz") %||% "Etc/GMT-12"
  lat <- lat %||% attr(era5, "lat")
  lon <- lon %||% attr(era5, "lon")

  hr <- if (is.null(bc)) era5 else
    apply_met_bias_correction(era5, bc, verbose = verbose)

  dl <- met_to_daily(hr, tz = tz, min_frac = min_frac)
  say("aggregated to ", nrow(dl), " days")

  if ("MET_pprain" %in% names(dl) && all(dl$MET_pprain == 0, na.rm = TRUE))
    warning("MET_pprain is zero throughout - downstream delta-change code ",
            "may substitute its own rainfall series")

  if (isTRUE(expand)) {
    if (is.null(lat) || is.null(lon))
      stop("expand = TRUE needs 'lat' and 'lon'.")
    keep <- attr(hr, "biascorr")
    dl <- expand_met(dl, lat = lat, lon = lon, elev = elev, tz = tz)
    attr(dl, "biascorr") <- keep
    attr(dl, "tz") <- tz; attr(dl, "lat") <- lat; attr(dl, "lon") <- lon
  }
  dl
}
