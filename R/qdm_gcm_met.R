## ---------------------------------------------------------------------------
## Trend-preserving quantile delta mapping of a climate-model daily series.
## ---------------------------------------------------------------------------

#' Quantile delta mapping of a climate-model series onto a corrected baseline
#'
#' The delta-change workflow ([scenario_workflow]) keeps the *baseline's*
#' weather and shifts its monthly means, so day-to-day variability, storms
#' and heatwaves stay as they were. `qdm_gcm_met()` is the alternative: use
#' the climate model's **own** daily series (its own sequence of weather and
#' extremes) and bias-correct it against the corrected baseline over a common
#' reference period with quantile delta mapping (Cannon et al. 2015).
#'
#' This is not what `method = "qdm"` in [fit_met_bias_correction()] does.
#' There the quantile of a value is read from the *training-period* CDF of
#' the series being corrected, which is a stationary correction: a future
#' value outside the training range is clamped to its end values. For a
#' climate projection the quantile must instead come from the model's own
#' *future* distribution, so that the projected change at each quantile
#' survives the correction.
#'
#' Per variable and calendar month, for a model value `x` in year `y`:
#'
#' \preformatted{
#' tau   = quantile of x within the model's window of `window_length` years
#'         centred on y (same calendar month)
#' x_obs = F_baseline_ref^-1(tau)
#' x_ref = F_model_ref^-1(tau)
#' additive:        corrected = x_obs + (x - x_ref)
#' multiplicative:  corrected = x_obs * (x / x_ref)      # ratio capped
#' }
#'
#' so the model's change at each quantile is kept while the reference-period
#' distribution is forced onto the baseline's.
#'
#' @param gcm daily model series from [extract_climate_point()] - `Date`,
#'   `experiment` and `MET_*` columns.
#' @param baseline daily corrected baseline with `Date` and the same `MET_*`
#'   columns, e.g. from [bias_correct_daily_baseline()]. Must be in the same
#'   units as `gcm`.
#' @param scenario name of the future experiment in `gcm$experiment`, e.g.
#'   `"ssp585"`. The `historical` experiment is always joined in front of it.
#' @param vars variables to correct; default is every `MET_*` column common to
#'   `gcm` and `baseline`.
#' @param ref_years years used to fit the two reference distributions. Default
#'   is the years present in both the baseline and the model's `historical`
#'   experiment. Should be at least about 15 years.
#' @param target_years years to return; default all model years in
#'   `historical` and `scenario`.
#' @param window_length length in years of the centred sliding window that
#'   defines the model's own future distribution (truncated at the ends of
#'   the record).
#' @param kind `"add"` or `"mult"` per variable, as a named vector. Defaults:
#'   `MET_tmpair` additive; `MET_wndspd`, `MET_radswd`, `MET_pprain`,
#'   `MET_ppsnow` and `MET_humrel` multiplicative. Variables not named take
#'   `"add"`.
#' @param ratio_cap upper cap on a multiplicative ratio.
#' @param wet_threshold corrected `MET_pprain` below this (same units as the
#'   data, default `1e-4`, i.e. 0.1 mm if the unit is m day-1) is set to zero,
#'   to remove the drizzle the mapping creates.
#' @param min_n minimum number of finite reference values per variable and
#'   month in each of `baseline` and `gcm`; fewer is an error.
#'
#' @return a data frame with `Date` and the corrected variables for
#'   `target_years`. Relative humidity is limited to 0-100. Attributes `lat`,
#'   `lon`, `tz` are carried over from `gcm` when present, and `qdm` holds the
#'   settings used. The dependent variables (pressure, longwave, ...) are not
#'   regenerated: pass the result to [expand_met()].
#'
#' @references Cannon, A.J., Sobie, S.R. and Murdock, T.Q. (2015). Bias
#'   correction of GCM precipitation by quantile mapping: how well do methods
#'   preserve changes in quantiles and extremes? *Journal of Climate* 28,
#'   6938-6959.
#'
#' @seealso [bias_correct_daily_baseline()], [extract_climate_point()],
#'   [fit_met_bias_correction()], [scenario_workflow]
#'
#' @examples
#' \dontrun{
#' cmip <- extract_climate_point("inst/extdata/rotorua_cmip6",
#'                               lon = 176.2717, lat = -38.0790)
#' base <- bias_correct_daily_baseline(era5, bc, expand = FALSE)
#' proj <- qdm_gcm_met(cmip, base, scenario = "ssp585",
#'                     ref_years = 1995:2014, target_years = 2015:2099)
#' proj <- expand_met(proj, lat = -38.079, lon = 176.2717)
#' }
#' @export
qdm_gcm_met <- function(gcm, baseline, scenario, vars = NULL,
                        ref_years = NULL, target_years = NULL,
                        window_length = 30, kind = NULL,
                        ratio_cap = 10, wet_threshold = 1e-4, min_n = 100) {
  stopifnot(is.data.frame(gcm), is.data.frame(baseline),
            all(c("Date", "experiment") %in% names(gcm)),
            "Date" %in% names(baseline),
            is.character(scenario), length(scenario) == 1)
  if (!"historical" %in% gcm$experiment)
    stop("'gcm' has no 'historical' experiment to fit the reference ",
         "distribution on.")
  if (!scenario %in% gcm$experiment)
    stop("scenario '", scenario, "' not in gcm$experiment (",
         paste(unique(gcm$experiment), collapse = ", "), ").")

  common <- intersect(grep("^MET_", names(gcm), value = TRUE),
                      grep("^MET_", names(baseline), value = TRUE))
  vars <- vars %||% common
  if (!length(vars) || !all(vars %in% common))
    stop("'vars' must be MET_* columns present in both 'gcm' and 'baseline'.")

  ## experiments: historical stitched to the scenario, one value per date
  g <- gcm[gcm$experiment %in% c("historical", scenario), , drop = FALSE]
  g <- g[order(g$Date), , drop = FALSE]
  g <- g[!duplicated(g$Date), , drop = FALSE]
  yr <- function(d) as.integer(format(d, "%Y"))
  mo <- function(d) as.integer(format(d, "%m"))
  gy <- yr(g$Date); gm <- mo(g$Date)
  by <- yr(baseline$Date); bm <- mo(baseline$Date)

  hist_years <- unique(gy[g$experiment == "historical"])
  ref_years <- ref_years %||% intersect(hist_years, unique(by))
  if (length(ref_years) < 10)
    stop("Fewer than 10 reference years in common between baseline and the ",
         "model's historical experiment; supply 'ref_years'.")
  target_years <- target_years %||% sort(unique(gy))

  ## kind per variable
  kind_default <- c(MET_tmpair = "add", MET_wndspd = "mult", MET_radswd = "mult",
                    MET_pprain = "mult", MET_ppsnow = "mult",
                    MET_humrel = "mult")
  k <- stats::setNames(rep("add", length(vars)), vars)
  k[intersect(vars, names(kind_default))] <- kind_default[intersect(vars, names(kind_default))]
  if (!is.null(kind)) {
    if (is.null(names(kind)) || !all(names(kind) %in% vars))
      stop("'kind' must be a named vector over 'vars'.")
    k[names(kind)] <- kind
  }
  if (!all(k %in% c("add", "mult"))) stop("'kind' must be \"add\" or \"mult\".")

  out <- g[, c("Date", vars), drop = FALSE]
  rownames(out) <- NULL
  half <- window_length %/% 2
  for (v in vars) {
    eps <- if (v %in% c("MET_pprain", "MET_ppsnow")) 1e-7 else 1e-6
    x_all <- g[[v]]; res <- x_all
    for (m in 1:12) {
      o_ref <- baseline[[v]][by %in% ref_years & bm == m]
      h_ref <- x_all[gy %in% ref_years & gm == m & g$experiment == "historical"]
      o_ref <- o_ref[is.finite(o_ref)]; h_ref <- h_ref[is.finite(h_ref)]
      if (length(o_ref) < min_n || length(h_ref) < min_n)
        stop(v, ", month ", m, ": fewer than ", min_n,
             " finite reference values (baseline ", length(o_ref),
             ", model ", length(h_ref), ").")
      for (y in intersect(target_years, unique(gy))) {
        i_t <- which(gy == y & gm == m)
        if (!length(i_t)) next
        lo <- max(min(gy), y - half + 1)
        hi <- min(max(gy), y + window_length - half)
        i_w <- which(gy >= lo & gy <= hi & gm == m & is.finite(x_all))
        w <- x_all[i_w]
        tau_w <- (rank(w, ties.method = "average") - 0.5) / length(w)
        ## value's own tau; non-finite values stay non-finite
        tau <- tau_w[match(i_t, i_w)]
        x <- x_all[i_t]
        ok <- is.finite(x) & is.finite(tau)
        if (!any(ok)) next
        q_o <- as.numeric(stats::quantile(o_ref, tau[ok], type = 7, names = FALSE))
        q_h <- as.numeric(stats::quantile(h_ref, tau[ok], type = 7, names = FALSE))
        xo <- x[ok]
        res[i_t[ok]] <- if (k[[v]] == "add") {
          q_o + (xo - q_h)
        } else {
          r <- ifelse(q_h < eps & xo < eps, 1, xo / pmax(q_h, eps))
          q_o * pmin(r, ratio_cap)
        }
      }
    }
    out[[v]] <- res
  }

  out <- out[gy %in% target_years, , drop = FALSE]
  rownames(out) <- NULL
  if ("MET_pprain" %in% vars && !is.null(wet_threshold))
    out$MET_pprain[is.finite(out$MET_pprain) &
                     out$MET_pprain < wet_threshold] <- 0
  if ("MET_humrel" %in% vars)
    out$MET_humrel <- pmin(pmax(out$MET_humrel, 0), 100)

  for (a in c("lat", "lon", "tz"))
    if (!is.null(attr(gcm, a))) attr(out, a) <- attr(gcm, a)
  attr(out, "qdm") <- list(scenario = scenario, ref_years = ref_years,
                           window_length = window_length, kind = k,
                           ratio_cap = ratio_cap, wet_threshold = wet_threshold)
  out
}
