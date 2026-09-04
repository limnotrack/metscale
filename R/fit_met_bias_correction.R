#' Fit a bias correction for ERA5-Land meteorology from local observations
#'
#' Joins an ERA5 met frame (from [extract_era5_hourly_met()] /
#' [extract_era5_lake_met()]) to a matching frame of locally measured
#' meteorology (from [prepare_obs_met()]) over their common period and
#' fits, per variable, a transfer function that maps ERA5 onto the
#' observations. The fitted object is applied to the full ERA5 record with
#' [apply_met_bias_correction()].
#'
#' Methods (set globally via `method`, or per variable with a named
#' vector):
#' \describe{
#'   \item{`"scale"`}{(default) a per-month offset - additive
#'     (`obs - era5`) or multiplicative (`sum(obs) / sum(era5)`), chosen by
#'     `transform`. With `by = "doy-loess"` the 12 monthly offsets are
#'     loess-smoothed across the day-of-year (as
#'     `nz_climate_projections/climate_shift.R`).}
#'   \item{`"variance"`}{per-month mean and standard-deviation matching:
#'     `mean_o + (x - mean_e) * sd_o / sd_e`.}
#'   \item{`"linear"`}{per-month least squares `obs ~ a + b * era5`
#'     (`robust = TRUE` uses `MASS::rlm`).}
#'   \item{`"eqm"`}{empirical quantile mapping per month - remap the ERA5
#'     CDF onto the observed CDF, linear interpolation, constant-tail
#'     extrapolation.}
#'   \item{`"qdm"`}{quantile delta mapping - as `"eqm"` but preserves the
#'     ERA5 anomaly relative to its training quantile, so trends/among-year
#'     signal survive extrapolation.}
#' }
#' Any stratum with fewer than `min_n` pairs falls back to the pooled
#' (all-month) fit. Shortwave is fitted on daytime records only.
#'
#' @param era5 data frame with `Date` plus `MET_*` columns (extractor output).
#' @param obs  data frame with `Date` plus `MET_*` columns
#'   ([prepare_obs_met()] output). Must be the same resolution and time
#'   zone as `era5`.
#' @param vars character vector of `MET_*` columns to correct. `NULL`
#'   (default) uses the columns common to both, excluding derived/direction
#'   fields (`MET_wnddir`, `MET_wnduvu`, `MET_wnduvv`, `MET_cldcvr`,
#'   `MET_prvapr`, `MET_prmslp`).
#' @param method `"scale"` (default), `"variance"`, `"linear"`, `"eqm"` or
#'   `"qdm"`; or a named vector, e.g.
#'   `c(MET_wndspd = "eqm", MET_tmpair = "scale")`.
#' @param transform `"auto"` (ratio for `MET_wndspd`/`MET_radswd`/
#'   `MET_pprain`/`MET_ppsnow`, additive otherwise), `"additive"` or
#'   `"ratio"`; or a named vector. Only used by `method = "scale"`.
#' @param by `"doy-loess"` (default), `"month"` or `"none"`. Coerced to
#'   `"month"` for methods other than `"scale"`.
#' @param cv `"loyo"` (leave-one-year-out, default) or `"none"` - controls
#'   whether the skill table includes out-of-sample rows.
#' @param min_n minimum paired records per monthly stratum (default 60).
#' @param loess_span span for the day-of-year loess (default 0.25).
#' @param robust use `MASS::rlm` for `method = "linear"` (default `FALSE`).
#' @param nquantiles number of quantiles for `"eqm"`/`"qdm"` (default 50).
#' @param cv_min_months a year is usable as a leave-one-out fold only if it
#'   has at least this many months of overlap (default 8).
#' @param swr_daytime_wm2 ERA5 shortwave threshold (W/m2) above which a
#'   record counts as daytime for the shortwave fit (default 5).
#' @param verbose print progress and the skill table.
#'
#' @return an object of class `met_biascorr`: a list with `models` (per
#'   variable), `skill` (data frame: `variable`, `stage` in
#'   `raw`/`corrected`/`cv_raw`/`cv_corrected`, `n`, `bias`, `mae`,
#'   `rmse`, `r`, `kge`), `training` (window, resolution, tz, years,
#'   station) and `call`.
#'
#' @seealso [prepare_obs_met()], [apply_met_bias_correction()]
#' @export
fit_met_bias_correction <- function(era5, obs,
                                    vars = NULL,
                                    method = "scale",
                                    transform = "auto",
                                    by = c("doy-loess", "month", "none"),
                                    cv = c("loyo", "none"),
                                    min_n = 60,
                                    cv_min_months = 8,
                                    loess_span = 0.25,
                                    robust = FALSE,
                                    nquantiles = 50,
                                    swr_daytime_wm2 = 5,
                                    verbose = TRUE) {

  by <- match.arg(by)
  cv <- match.arg(cv)
  say <- function(...) if (isTRUE(verbose)) message(...)
  ratio_default <- c("MET_wndspd", "MET_radswd", "MET_pprain", "MET_ppsnow")

  stopifnot(is.data.frame(era5), is.data.frame(obs),
            "Date" %in% names(era5), "Date" %in% names(obs))

  ## ---- align on Date --------------------------------------------------
  e <- era5; o <- obs
  daily <- inherits(e$Date, "Date") || inherits(o$Date, "Date")
  keyfun <- if (daily) function(d) as.character(as.Date(d))
            else       function(d) format(as.POSIXct(d), "%Y-%m-%d %H:%M")
  e$.k <- keyfun(e$Date); o$.k <- keyfun(o$Date)
  common <- intersect(e$.k, o$.k)
  if (length(common) < min_n)
    stop("Only ", length(common), " overlapping timestamps between era5 and obs.")

  ecols <- setdiff(names(e), c("Date", ".k"))
  ocols <- setdiff(names(o), c("Date", ".k"))
  if (is.null(vars)) {
    vars <- setdiff(intersect(ecols, ocols),
                    c("MET_wnddir", "MET_wnduvu", "MET_wnduvv",
                      "MET_cldcvr", "MET_prvapr", "MET_prmslp"))
  } else {
    miss <- setdiff(vars, intersect(ecols, ocols))
    if (length(miss)) warning("Not in both era5 and obs, skipped: ",
                              paste(miss, collapse = ", "))
    vars <- intersect(vars, intersect(ecols, ocols))
  }
  if (!length(vars)) stop("No common correctable variables.")

  em <- e[match(common, e$.k), , drop = FALSE]
  om <- o[match(common, o$.k), , drop = FALSE]
  Date <- em$Date
  yr  <- as.integer(format(as.POSIXct(Date), "%Y"))
  mon <- as.integer(format(as.POSIXct(Date), "%m"))
  doy <- as.integer(format(as.POSIXct(Date), "%j"))
  say("Overlap: ", format(min(Date)), " to ", format(max(Date)),
      "  (", length(common), " records, ", length(unique(yr)), " years)")
  ## years usable as leave-one-out folds: those with enough month coverage
  mcov <- tapply(mon, yr, function(m) length(unique(m)))
  cv_years <- as.integer(names(mcov)[mcov >= cv_min_months])

  perVar <- function(x, nm, dflt) {
    if (length(x) == 1L && is.null(names(x))) return(stats::setNames(rep(x, length(nm)), nm))
    out <- stats::setNames(rep(dflt, length(nm)), nm)
    out[names(x)] <- x
    out
  }
  method_v    <- perVar(method, vars, "scale")
  transform_v <- perVar(transform, vars, "auto")
  ## these are looked up by name below; strip names off the values so the
  ## stored models do not carry a stray name attribute
  method_v    <- stats::setNames(unname(method_v), names(method_v))
  transform_v <- stats::setNames(unname(transform_v), names(transform_v))
  for (v in vars) if (transform_v[v] == "auto")
    transform_v[v] <- if (v %in% ratio_default) "ratio" else "additive"

  ## ================= internal fit / predict ========================
  # month_factor (length-12, NA where thin) -> smooth daily (length-366)
  smooth_doy <- function(mf) {
    mid <- c(15.5, 45, 74.5, 105, 135.5, 166, 196.5, 227.5, 258, 288.5, 319, 349.5)
    ok <- is.finite(mf)
    d <- data.frame(doy = c(mid[ok] - 366, mid[ok], mid[ok] + 366),
                    f   = rep(mf[ok], 3))
    if (sum(ok) < 4) return(stats::setNames(rep(mean(mf, na.rm = TRUE), 366), 1:366))
    fit <- stats::loess(f ~ doy, data = d, span = loess_span)
    stats::setNames(as.numeric(stats::predict(fit, newdata = data.frame(doy = 1:366))), 1:366)
  }

  fit_one <- function(vv, meth, tr, mm, bymode, ob, er) {
    keep <- is.finite(ob) & is.finite(er)
    if (vv == "MET_radswd") keep <- keep & (er > swr_daytime_wm2)
    ob <- ob[keep]; er <- er[keep]; mm <- mm[keep]
    strata <- split(seq_along(ob), mm)
    pooled <- seq_along(ob)
    enough <- function(ix) !is.null(ix) && length(ix) >= min_n

    if (meth == "scale") {
      mf <- rep(NA_real_, 12)
      calc <- function(ix) if (tr == "ratio")
        (if (sum(er[ix]) > 0) sum(ob[ix]) / sum(er[ix]) else 1) else mean(ob[ix] - er[ix])
      for (m in 1:12) {
        ix <- strata[[as.character(m)]]
        mf[m] <- if (enough(ix)) calc(ix) else NA_real_
      }
      pooled_f <- calc(pooled)
      mf[is.na(mf)] <- pooled_f
      daily_f <- if (bymode == "doy-loess") smooth_doy(mf) else NULL
      list(method = "scale", transform = tr, by = bymode,
           month_factor = mf, daily_factor = daily_f, pooled = pooled_f)

    } else if (meth == "variance") {
      M <- matrix(NA_real_, 12, 4,
                  dimnames = list(NULL, c("mo", "so", "me", "se")))
      for (m in 1:12) {
        ix <- strata[[as.character(m)]]
        if (enough(ix))
          M[m, ] <- c(mean(ob[ix]), stats::sd(ob[ix]), mean(er[ix]), stats::sd(er[ix]))
      }
      pr <- c(mean(ob), stats::sd(ob), mean(er), stats::sd(er))
      for (m in 1:12) if (anyNA(M[m, ])) M[m, ] <- pr
      list(method = "variance", by = "month", par = M, pooled = pr)

    } else if (meth == "linear") {
      C <- matrix(NA_real_, 12, 2, dimnames = list(NULL, c("a", "b")))
      lmfit <- function(ix) {
        df <- data.frame(obs = ob[ix], era5 = er[ix])
        cf <- if (isTRUE(robust) && requireNamespace("MASS", quietly = TRUE))
          tryCatch(stats::coef(MASS::rlm(obs ~ era5, df)), error = function(e) NULL)
        else stats::coef(stats::lm(obs ~ era5, df))
        if (is.null(cf) || anyNA(cf)) NULL else unname(cf)
      }
      pr <- lmfit(pooled); if (is.null(pr)) pr <- c(0, 1)
      for (m in 1:12) {
        ix <- strata[[as.character(m)]]
        cf <- if (enough(ix)) lmfit(ix) else NULL
        C[m, ] <- if (is.null(cf)) pr else cf
      }
      list(method = "linear", by = "month", coef = C, pooled = pr)

    } else {  # eqm / qdm
      p <- seq(0, 1, length.out = nquantiles)
      qfun <- function(ix) list(qe = as.numeric(stats::quantile(er[ix], p, names = FALSE, type = 7)),
                                qo = as.numeric(stats::quantile(ob[ix], p, names = FALSE, type = 7)))
      pr <- qfun(pooled)
      Q <- vector("list", 12)
      for (m in 1:12) {
        ix <- strata[[as.character(m)]]
        Q[[m]] <- if (enough(ix)) qfun(ix) else pr
      }
      list(method = meth, by = "month", p = p, q = Q, pooled = pr,
           transform = if (vv %in% ratio_default) "ratio" else "additive")
    }
  }

  predict_one <- function(model, x, month, doy) .mbc_predict(model, x, month, doy)

  ## ================= fit each variable + skill ======================
  skill_rows <- list()
  add_skill <- function(v, stage, o_, m_) {
    ok <- is.finite(o_) & is.finite(m_)
    o_ <- o_[ok]; m_ <- m_[ok]
    if (length(o_) < 2) return(invisible())
    r  <- suppressWarnings(stats::cor(o_, m_))
    kge <- 1 - sqrt((r - 1)^2 +
                    (stats::sd(m_) / stats::sd(o_) - 1)^2 +
                    (mean(m_) / mean(o_) - 1)^2)
    skill_rows[[length(skill_rows) + 1]] <<- data.frame(
      variable = v, stage = stage, n = length(o_),
      bias = mean(m_ - o_), mae = mean(abs(m_ - o_)),
      rmse = sqrt(mean((m_ - o_)^2)), r = r, kge = kge)
  }

  models <- list()
  for (v in vars) {
    ob <- om[[v]]; er <- em[[v]]
    md <- if (method_v[v] == "scale") by else "month"
    if (by == "doy-loess" && method_v[v] != "scale")
      say("  ", v, ": '", method_v[v], "' uses monthly strata (no doy-loess)")
    if (sum(is.finite(ob) & is.finite(er)) < min_n) {
      warning(v, ": < ", min_n, " paired records - not corrected"); next
    }
    mdl <- fit_one(v, unname(method_v[v]), unname(transform_v[v]), mon, md, ob, er)
    fitted <- .mbc_predict(mdl, er, mon, doy)
    models[[v]] <- mdl
    add_skill(v, "raw", ob, er)
    add_skill(v, "corrected", ob, fitted)

    if (cv == "loyo" && length(cv_years) >= 2) {
      cvr <- rep(NA_real_, length(er))
      for (Y in cv_years) {
        tr <- yr != Y; te <- yr == Y
        if (sum(is.finite(ob[tr]) & is.finite(er[tr])) < min_n) next
        m_cv <- fit_one(v, unname(method_v[v]), unname(transform_v[v]),
                        mon[tr], md, ob[tr], er[tr])
        cvr[te] <- .mbc_predict(m_cv, er[te], mon[te], doy[te])
      }
      add_skill(v, "cv_raw", ifelse(is.finite(cvr), ob, NA_real_), er)
      add_skill(v, "cv_corrected", ob, cvr)
    } else if (cv == "loyo" && v == vars[1]) {
      say("  (leave-one-year-out CV skipped: need >= 2 years with >= ",
          cv_min_months, " months of overlap)")
    }
    say("  ", v, ": ", method_v[v],
        if (method_v[v] == "scale") paste0(" (", transform_v[v], ", ", md, ")") else "")
  }
  if (!length(models)) stop("No variable could be corrected.")

  skill <- do.call(rbind, skill_rows)
  rownames(skill) <- NULL
  num <- sapply(skill, is.numeric)
  skill[num] <- lapply(skill[num], function(x) round(x, 4))

  out <- list(
    models = models,
    skill  = skill,
    training = list(start = min(Date), end = max(Date),
                    n_overlap = length(common),
                    resolution = if (daily) "daily" else "sub-daily",
                    tz = attr(obs, "tz") %||% NA_character_,
                    years = sort(unique(yr)),
                    station = attr(obs, "station") %||% NA_character_),
    vars = vars, call = match.call())
  class(out) <- c("met_biascorr", "list")
  if (isTRUE(verbose)) print(out)
  invisible(out)
}

#' Apply one fitted per-variable bias-correction model to a vector
#'
#' Internal - shared by [fit_met_bias_correction()] (in-sample / CV) and
#' [apply_met_bias_correction()].
#'
#' @param model one element of `met_biascorr$models`.
#' @param x numeric ERA5 values.
#' @param month,doy integer month (1-12) and day-of-year (1-366) vectors,
#'   same length as `x`.
#' @return numeric vector of corrected values.
#' @noRd
.mbc_predict <- function(model, x, month, doy) {
  out <- x
  if (model$method == "scale") {
    f <- if (!is.null(model$daily_factor)) model$daily_factor[pmin(doy, 366)]
         else model$month_factor[month]
    out <- if (model$transform == "ratio") x * f else x + f

  } else if (model$method == "variance") {
    P <- model$par[month, , drop = FALSE]
    out <- P[, "mo"] + (x - P[, "me"]) * P[, "so"] / P[, "se"]

  } else if (model$method == "linear") {
    C <- model$coef[month, , drop = FALSE]
    out <- C[, "a"] + C[, "b"] * x

  } else if (model$method %in% c("eqm", "qdm")) {
    for (m in unique(month)) {
      ii <- which(month == m); qq <- model$q[[m]]
      pv <- stats::approx(qq$qe, model$p, xout = x[ii], rule = 2, ties = "ordered")$y
      mapped <- stats::approx(model$p, qq$qo, xout = pv, rule = 2, ties = "ordered")$y
      if (model$method == "qdm") {
        qe_at <- stats::approx(model$p, qq$qe, xout = pv, rule = 2, ties = "ordered")$y
        out[ii] <- if (model$transform == "ratio")
          x[ii] * ifelse(qe_at != 0, mapped / qe_at, 1) else x[ii] + (mapped - qe_at)
      } else out[ii] <- mapped
    }
  }
  out
}

#' @export
print.met_biascorr <- function(x, ...) {
  tr <- x$training
  cat("<met_biascorr>\n")
  cat(sprintf("  training : %s -> %s  (%s records, %s)\n",
              format(tr$start), format(tr$end), tr$n_overlap, tr$resolution))
  cat(sprintf("  years    : %s\n", paste(range(tr$years), collapse = "-")))
  if (!is.na(tr$station)) cat(sprintf("  station  : %s\n", tr$station))
  cat("  methods  :\n")
  for (v in names(x$models))
    cat(sprintf("    %-11s %s%s\n", v, x$models[[v]]$method,
                if (!is.null(x$models[[v]]$transform))
                  paste0(" [", x$models[[v]]$transform, "]") else ""))
  cat("  skill (obs vs ...):\n")
  print(x$skill, row.names = FALSE)
  invisible(x)
}

#' @export
plot.met_biascorr <- function(x, era5 = NULL, obs = NULL, ...) {
  vs <- names(x$models)
  op <- graphics::par(mfrow = grDevices::n2mfrow(length(vs)),
                      mar = c(4, 4, 2, 1)); on.exit(graphics::par(op))
  for (v in vs) {
    s <- x$skill[x$skill$variable == v, ]
    raw <- s[s$stage %in% c("cv_raw", "raw"), ][1, ]
    cor <- s[s$stage %in% c("cv_corrected", "corrected"), ][1, ]
    graphics::barplot(c(raw = raw$rmse, corrected = cor$rmse),
                      main = v, ylab = "RMSE", col = c("grey70", "steelblue"))
  }
  invisible(x)
}
