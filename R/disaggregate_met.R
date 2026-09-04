## ---------------------------------------------------------------------------
## Temporal disaggregation of daily meteorology to sub-daily, borrowing the
## diurnal structure of an hourly reanalysis record for the same location.
## ---------------------------------------------------------------------------

## Variables whose daily value is a total rather than a mean.
.sum_vars   <- c("MET_pprain", "MET_ppsnow")
## Variables disaggregated multiplicatively (bounded at zero, strongly
## shaped); everything else additively about the daily mean.
.ratio_vars <- c("MET_wndspd", "MET_radswd", "MET_pprain", "MET_ppsnow")

#' Reshape an hourly record into a day x hour matrix per variable
#' @noRd
.day_matrix <- function(hourly, tz, vars, n_sub = 24) {
  d  <- as.POSIXct(hourly$Date)
  day <- as.Date(d, tz = tz)
  slot <- as.integer(format(d, "%H", tz = tz)) %/% (24L / n_sub) + 1L
  udays <- sort(unique(day))
  di <- match(day, udays)

  out <- lapply(vars, function(v) {
    m <- matrix(NA_real_, length(udays), n_sub)
    m[cbind(di, slot)] <- hourly[[v]]
    m
  })
  names(out) <- vars
  complete <- Reduce(`&`, lapply(out, function(m) rowSums(is.na(m)) == 0))
  list(days = udays[complete],
       mat  = lapply(out, function(m) m[complete, , drop = FALSE]))
}

#' Daily aggregate of a day x slot matrix, respecting sum vs mean variables
#' @noRd
.day_agg <- function(m, v) if (v %in% .sum_vars) rowSums(m) else rowMeans(m)

## Physical bounds for the disaggregated variables.
.met_bounds <- list(
  MET_humrel = c(0, 100), MET_cldcvr = c(0, 1),
  MET_wndspd = c(0, Inf), MET_radswd = c(0, Inf), MET_radlwd = c(0, Inf),
  MET_pprain = c(0, Inf), MET_ppsnow = c(0, Inf)
)

#' Impose bounds on a day x slot matrix without breaking conservation
#'
#' Clamping a disaggregated series to physical limits shifts its daily
#' aggregate. This clamps, then redistributes the resulting surplus or
#' deficit across the steps that still have headroom, and repeats until the
#' daily aggregate is restored (or no headroom remains).
#'
#' @param M numeric matrix, days by sub-daily steps.
#' @param target the daily aggregate each row must reproduce.
#' @param lo,hi bounds.
#' @param sum_type `TRUE` when the daily aggregate is a total, `FALSE` for
#'   a mean.
#' @param iter maximum redistribution passes.
#' @return the adjusted matrix.
#' @noRd
.clamp_conserving <- function(M, target, lo = -Inf, hi = Inf,
                              sum_type = FALSE, iter = 30) {
  n <- ncol(M)
  for (k in seq_len(iter)) {
    M <- pmin(pmax(M, lo), hi)
    cur <- if (sum_type) rowSums(M) else rowMeans(M)
    d <- target - cur
    d[!is.finite(d)] <- 0
    if (all(abs(d) < 1e-10)) break
    ## the test must be a matrix, or ifelse() drops the dimensions
    up <- matrix(d > 0, nrow(M), ncol(M))
    room <- ifelse(up, hi - M, M - lo)
    room[!is.finite(room)] <- 1        # unbounded on that side
    room[room < 0] <- 0
    tot <- rowSums(room)
    scale <- ifelse(tot > 0, (if (sum_type) d else d * n) / tot, 0)
    M <- M + room * scale
  }
  pmin(pmax(M, lo), hi)
}

#' Mean diurnal cycle of an hourly meteorological record
#'
#' Summarises an hourly record into, for each variable and calendar month,
#' the average shape of the day: an anomaly about the daily mean for
#' additive variables (temperature, humidity, pressure, longwave) and a
#' normalised factor for multiplicative ones (wind speed, shortwave,
#' precipitation). Used by [disaggregate_met_to_hourly()] with
#' `method = "diurnal"`.
#'
#' @param hourly data frame with `Date` (POSIXct) and `MET_*` columns, e.g.
#'   from [extract_era5_lake_met()].
#' @param tz timezone in which the diurnal cycle is expressed. Defaults to
#'   the `tz` attribute of `hourly`, else `"Etc/GMT-12"`.
#' @param vars variables to summarise; default all `MET_*` columns present.
#' @param n_sub steps per day (24 hourly, 8 three-hourly).
#'
#' @return object of class `diurnal_climatology`: a list with `shape` (a
#'   named list of `12 x n_sub` matrices), `kind` (`"additive"` or
#'   `"ratio"` per variable), `n_days` per month, `tz` and `n_sub`.
#'
#' @examples
#' set.seed(1)
#' h <- data.frame(
#'   Date = seq(as.POSIXct("2024-01-01", tz = "Etc/GMT-12"),
#'              by = "hour", length.out = 24 * 60),
#'   MET_tmpair = 15 + 5 * sin(seq_len(24 * 60) * 2 * pi / 24) + rnorm(24 * 60))
#' dc <- build_diurnal_climatology(h)
#' round(dc$shape$MET_tmpair[1, ], 2)
#' @export
build_diurnal_climatology <- function(hourly, tz = NULL, vars = NULL,
                                      n_sub = 24) {
  stopifnot(is.data.frame(hourly), "Date" %in% names(hourly))
  tz <- tz %||% attr(hourly, "tz") %||% "Etc/GMT-12"
  if (is.null(vars)) vars <- grep("^MET_", names(hourly), value = TRUE)
  vars <- intersect(vars, names(hourly))
  if (!length(vars)) stop("no MET_* columns found in 'hourly'")

  dm  <- .day_matrix(hourly, tz, vars, n_sub)
  if (!length(dm$days)) stop("no complete days in 'hourly'")
  mon <- as.integer(format(dm$days, "%m"))

  shape <- list(); kind <- character(0)
  for (v in vars) {
    m   <- dm$mat[[v]]
    agg <- .day_agg(m, v)
    k   <- if (v %in% .ratio_vars) "ratio" else "additive"
    rel <- if (k == "ratio") m / ifelse(agg > 0, agg, NA_real_) else m - agg
    s <- matrix(NA_real_, 12, n_sub)
    for (mo in 1:12) {
      ix <- which(mon == mo)
      if (length(ix)) s[mo, ] <- colMeans(rel[ix, , drop = FALSE], na.rm = TRUE)
    }
    ## months with no data fall back to the all-year mean
    gap <- rowSums(is.na(s)) > 0
    if (any(gap) && any(!gap)) s[gap, ] <- rep(colMeans(s[!gap, , drop = FALSE]),
                                               each = sum(gap))
    if (all(gap)) stop("could not build a diurnal cycle for ", v)
    ## renormalise so applying the shape is conservative by construction:
    ## additive shapes average to 0, multiplicative ones to 1 (or sum to 1
    ## for the accumulating variables)
    s <- if (k != "ratio") {
      s - rowMeans(s)
    } else if (v %in% .sum_vars) {
      tot <- rowSums(s); tot[tot <= 0] <- 1
      s / tot
    } else {
      mu <- rowMeans(s); mu[mu <= 0] <- 1
      s / mu
    }
    shape[[v]] <- s
    kind[v] <- k
  }
  out <- list(shape = shape, kind = kind, tz = tz, n_sub = n_sub,
              n_days = as.integer(table(factor(mon, levels = 1:12))))
  class(out) <- c("diurnal_climatology", "list")
  out
}

#' @export
print.diurnal_climatology <- function(x, ...) {
  cat("<diurnal_climatology>\n")
  cat("  tz        :", x$tz, "\n")
  cat("  steps/day :", x$n_sub, "\n")
  cat("  days/month:", paste(x$n_days, collapse = " "), "\n")
  cat("  variables :\n")
  for (v in names(x$shape))
    cat(sprintf("    %-11s %s\n", v, x$kind[[v]]))
  invisible(x)
}

#' Disaggregate daily meteorology to hourly or 3-hourly
#'
#' Distributes daily meteorology across the day using the diurnal structure
#' of an hourly reanalysis record for the same location, so that a daily
#' series - a bias-corrected daily record, or a climate-scenario series from
#' a delta-change step - can drive a sub-daily lake model. Daily means (and
#' daily rainfall totals) are conserved exactly, with one deliberate
#' exception: if the wind vector components `MET_wnduvu` / `MET_wnduvv` are
#' present they are shaped directly and `MET_wndspd` is recomputed from
#' them, so the disaggregated speed re-aggregates to the magnitude of the
#' daily *vector* mean rather than to a supplied daily *scalar* mean speed
#' (the former is the smaller of the two).
#'
#' Two ways of borrowing the structure:
#' \describe{
#'   \item{`"fragments"`}{(default) the *method of fragments*: for each
#'     target day an analogue day is chosen from the donor record - close in
#'     day-of-year and, when `match_on_value`, close in daily values - and
#'     its within-day shape is applied to every variable at once. Because a
#'     single donor day supplies all variables, the temperature, humidity
#'     and wind sub-daily patterns stay mutually consistent, and day-to-day
#'     variability in the shape is retained.}
#'   \item{`"diurnal"`}{a deterministic month-by-hour mean diurnal cycle
#'     from [build_diurnal_climatology()]. Smoother and reproducible, but
#'     every day of a given month gets the same shape.}
#' }
#'
#' Shortwave radiation is handled separately and by default comes from
#' solar geometry ([estimate_hourly_swr()]), which guarantees a
#' single-peaked curve, true night-time zeros and a peak at local solar
#' noon. Rainfall in `"fragments"` mode borrows its shape from a *wet*
#' donor day, chosen by closeness of daily total, so that wet-hour
#' intermittency is preserved; a dry target day stays dry throughout.
#'
#' Variables present in `daily` but not in `donor` are held constant
#' through each day. Wind direction (`MET_wnddir`) is never shaped about a
#' daily mean - it is recomputed from the disaggregated `MET_wnduvu` /
#' `MET_wnduvv` when those are present, otherwise held constant per day.
#'
#' @param daily data frame with `Date` (class `Date`, or daily POSIXct) and
#'   `MET_*` columns. Rainfall and snowfall are treated as daily totals,
#'   every other variable as a daily mean.
#' @param donor hourly data frame with `Date` (POSIXct) and `MET_*`
#'   columns for the same location, e.g. from [extract_era5_lake_met()].
#'   A longer donor record gives a better analogue pool.
#' @param method `"fragments"` (default) or `"diurnal"`.
#' @param timestep `"hour"` (default) or `"3hour"`.
#' @param swr `"clearsky"` (default) to rebuild shortwave from solar
#'   geometry, or `"shape"` to treat it like any other multiplicative
#'   variable. `"clearsky"` needs `lat` and `lon`.
#' @param interval what a timestamp denotes, passed to
#'   [estimate_hourly_swr()]. Default `"ending"`, matching the accumulated
#'   flux convention of ERA5 and of [extract_era5_hourly_met()].
#' @param lat,lon location in decimal degrees; taken from the `lat` / `lon`
#'   attributes of `daily` or `donor` when `NULL`.
#' @param elev elevation, m, used only when `expand = TRUE`.
#' @param tz timezone of `daily` and of the output. Defaults to the `tz`
#'   attribute of `daily`, then of `donor`, else `"Etc/GMT-12"`.
#' @param analogue_window half-width, in days of the year, of the donor
#'   pool for `method = "fragments"` (default 15).
#' @param match_on_value rank candidate donor days by similarity of their
#'   daily values, not just day-of-year (default `TRUE`).
#' @param sample_top_k sample the donor uniformly from the `k` best
#'   candidates instead of always taking the closest. `1` (default) is
#'   deterministic; larger values add realistic variety.
#' @param blend_hours smooth the borrowed shape across midnight over this
#'   many steps either side, to avoid a sawtooth discontinuity in
#'   temperature and humidity (default 2; `0` disables). Daily aggregates
#'   are restored afterwards, so conservation is unaffected. Never applied
#'   to rainfall or snowfall.
#' @param seed optional RNG seed, for reproducibility when
#'   `sample_top_k > 1`.
#' @param expand run [expand_met()] on the result to regenerate the
#'   dependent variables at the new timestep.
#' @param verbose print progress.
#'
#' @return data frame with `Date` (POSIXct in `tz`, regular sub-daily
#'   steps) and the same `MET_*` columns as `daily`. Attributes `tz`,
#'   `method`, `timestep`, and `donor_days` (the analogue chosen for each
#'   target day, `method = "fragments"` only).
#'
#' @seealso [build_diurnal_climatology()], [estimate_hourly_swr()],
#'   [met_to_daily()] for the reverse operation.
#'
#' @examples
#' set.seed(1)
#' ## donor: two years of synthetic hourly data with a diurnal cycle
#' t <- seq(as.POSIXct("2022-01-01", tz = "Etc/GMT-12"), by = "hour",
#'          length.out = 24 * 730)
#' hr <- as.integer(format(t, "%H"))
#' donor <- data.frame(Date = t,
#'                     MET_tmpair = 15 + 5 * sin((hr - 9) / 24 * 2 * pi) + rnorm(length(t)),
#'                     MET_wndspd = pmax(0.1, 4 + 2 * sin((hr - 12) / 24 * 2 * pi)))
#' ## daily series to disaggregate
#' daily <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 10),
#'                     MET_tmpair = rnorm(10, 16, 2),
#'                     MET_wndspd = runif(10, 2, 7))
#' out <- disaggregate_met_to_hourly(daily, donor, swr = "shape", verbose = FALSE)
#' head(out)
#' @export
disaggregate_met_to_hourly <- function(daily, donor,
                                       method = c("fragments", "diurnal"),
                                       timestep = c("hour", "3hour"),
                                       swr = c("clearsky", "shape"),
                                       interval = c("ending", "beginning",
                                                    "instant"),
                                       lat = NULL, lon = NULL, elev = 0,
                                       tz = NULL,
                                       analogue_window = 15,
                                       match_on_value = TRUE,
                                       sample_top_k = 1,
                                       blend_hours = 2,
                                       seed = NULL,
                                       expand = FALSE,
                                       verbose = TRUE) {

  method   <- match.arg(method)
  timestep <- match.arg(timestep)
  swr      <- match.arg(swr)
  interval <- match.arg(interval)
  say <- function(...) if (isTRUE(verbose)) message(...)
  if (!is.null(seed)) set.seed(seed)

  stopifnot(is.data.frame(daily), is.data.frame(donor),
            "Date" %in% names(daily), "Date" %in% names(donor))
  tz  <- tz  %||% attr(daily, "tz") %||% attr(donor, "tz") %||% "Etc/GMT-12"
  lat <- lat %||% attr(daily, "lat") %||% attr(donor, "lat")
  lon <- lon %||% attr(daily, "lon") %||% attr(donor, "lon")
  if (swr == "clearsky" && (is.null(lat) || is.null(lon)))
    stop("swr = 'clearsky' needs 'lat' and 'lon'.")

  tgt_days <- as.Date(daily$Date)
  vars <- grep("^MET_", names(daily), value = TRUE)
  if (!length(vars)) stop("no MET_* columns in 'daily'")

  ## shortwave is rebuilt from solar geometry, not borrowed; wind
  ## direction is circular and is derived from the u/v components (or, if
  ## those are absent, held constant), never shaped about a daily mean
  swr_clear <- swr == "clearsky" && "MET_radswd" %in% vars
  ## when u/v are present the wind vector is the primary representation:
  ## shape u and v, derive speed and direction from them. A daily *scalar*
  ## mean speed is larger than the magnitude of the daily *vector* mean, so
  ## the derived MET_wndspd will not re-aggregate to a supplied scalar
  ## MET_wndspd - by design.
  wind_uv   <- all(c("MET_wnduvu", "MET_wnduvv") %in% vars)
  special   <- c(if (swr_clear) "MET_radswd", "MET_wnddir",
                 if (wind_uv) "MET_wndspd")
  shape_vars <- setdiff(vars, special)
  donor_vars <- intersect(shape_vars, names(donor))
  carried <- setdiff(shape_vars, donor_vars)
  if (length(carried))
    say("held constant through the day (not in donor): ",
        paste(carried, collapse = ", "))

  ## ---- output time grid, in tz ---------------------------------------
  n_sub  <- if (timestep == "hour") 24L else 8L
  step_h <- 24L / n_sub
  base <- as.POSIXct(paste0(format(tgt_days), " 00:00:00"), tz = tz)
  Date <- rep(base, each = n_sub) +
          rep(seq(0, 24 - step_h, by = step_h) * 3600, times = length(base))
  nd <- length(tgt_days)
  out <- data.frame(Date = Date)

  ## ---- donor day library ---------------------------------------------
  if (length(donor_vars)) {
    dm <- .day_matrix(donor, tz, donor_vars, n_sub)
    if (!length(dm$days)) stop("no complete donor days at this timestep")
    say("donor pool: ", length(dm$days), " complete days (",
        format(min(dm$days)), " to ", format(max(dm$days)), ")")
    d_agg <- lapply(donor_vars, function(v) .day_agg(dm$mat[[v]], v))
    names(d_agg) <- donor_vars
    d_doy <- as.integer(format(dm$days, "%j"))
  }

  ## ---- choose an analogue donor day per target day --------------------
  pick <- rep(NA_integer_, nd)
  if (method == "fragments" && length(donor_vars)) {
    t_doy <- as.integer(format(tgt_days, "%j"))
    w <- c(MET_tmpair = 2, MET_wndspd = 1.5, MET_radswd = 1,
           MET_humrel = 1, MET_tmpdew = 1)
    mvars <- intersect(donor_vars, names(daily))
    ## exclude precipitation from state matching - it gets its own donor
    mvars <- setdiff(mvars, .sum_vars)
    sdv <- vapply(mvars, function(v) stats::sd(d_agg[[v]], na.rm = TRUE), 1)
    sdv[!is.finite(sdv) | sdv == 0] <- 1
    wt <- ifelse(mvars %in% names(w), w[mvars], 0.5)

    for (i in seq_len(nd)) {
      dd <- abs(d_doy - t_doy[i])
      dd <- pmin(dd, 366 - dd)
      cand <- which(dd <= analogue_window)
      if (!length(cand)) cand <- order(dd)[seq_len(min(50, length(dd)))]
      score <- rep(0, length(cand))
      if (isTRUE(match_on_value) && length(mvars)) {
        for (j in seq_along(mvars)) {
          v <- mvars[j]
          if (!v %in% names(daily)) next
          score <- score + wt[j] *
            abs(d_agg[[v]][cand] - daily[[v]][i])^2 / sdv[j]^2
        }
      }
      score <- score + 1e-6 * dd[cand]
      ord <- order(score)
      k <- max(1L, min(as.integer(sample_top_k), length(ord)))
      pick[i] <- cand[ord[if (k == 1L) 1L else sample.int(k, 1L)]]
    }
    say("analogue days chosen (window +/- ", analogue_window, " doy, top-k ",
        sample_top_k, ")")
  }

  ## ---- assemble each variable ----------------------------------------
  dc <- if (method == "diurnal" && length(donor_vars))
    build_diurnal_climatology(donor, tz = tz, vars = donor_vars, n_sub = n_sub)
  else NULL
  t_mon <- as.integer(format(tgt_days, "%m"))

  smooth_seam <- function(M, kind) {
    ## M is nd x n_sub; smooth across the midnight join only
    if (blend_hours <= 0 || nd < 2) return(M)
    v <- as.numeric(t(M))
    b <- min(as.integer(blend_hours), n_sub %/% 2)
    idx <- unlist(lapply(seq_len(nd - 1), function(i)
      (i * n_sub - b + 1):(i * n_sub + b)))
    idx <- idx[idx >= 2 & idx <= length(v) - 1]
    if (length(idx)) v[idx] <- (v[idx - 1] + 2 * v[idx] + v[idx + 1]) / 4
    M2 <- matrix(v, nd, n_sub, byrow = TRUE)
    ## restore conservation of the shape
    if (kind == "additive") M2 - rowMeans(M2) else M2 / rowMeans(M2)
  }

  for (v in shape_vars) {
    tval <- daily[[v]]
    if (!v %in% donor_vars) {                       # no donor - hold flat
      out[[v]] <- rep(if (v %in% .sum_vars) tval / n_sub else tval, each = n_sub)
      next
    }
    kind <- if (v %in% .ratio_vars) "ratio" else "additive"
    M <- dm$mat[[v]]

    if (method == "fragments") {
      sel <- pick
      if (v %in% .sum_vars) {
        ## rainfall: borrow from a wet day of similar total
        tot <- d_agg[[v]]
        wet <- which(tot > 0)
        sel <- vapply(seq_len(nd), function(i) {
          if (!is.finite(tval[i]) || tval[i] <= 0) return(NA_integer_)
          if (!length(wet)) return(NA_integer_)
          dd <- abs(d_doy[wet] - as.integer(format(tgt_days[i], "%j")))
          dd <- pmin(dd, 366 - dd)
          cand <- wet[dd <= analogue_window * 3]
          if (!length(cand)) cand <- wet
          cand[which.min(abs(tot[cand] - tval[i]))]
        }, integer(1))
      }
      shp <- matrix(NA_real_, nd, n_sub)
      ok <- !is.na(sel)
      if (any(ok)) {
        Ms  <- M[sel[ok], , drop = FALSE]
        agg <- .day_agg(Ms, v)
        shp[ok, ] <- if (kind == "ratio")
          Ms / ifelse(agg > 0, agg, NA_real_) else Ms - agg
      }
      ## fall back to a flat shape where no donor was usable
      flat <- if (kind == "ratio") 1 else 0
      shp[!stats::complete.cases(shp), ] <- flat
      if (v %in% .sum_vars) shp[is.na(sel), ] <- 0
    } else {
      shp <- dc$shape[[v]][t_mon, , drop = FALSE]
    }

    if (!(v %in% .sum_vars)) shp <- smooth_seam(shp, kind)

    val <- if (kind == "ratio") {
      if (v %in% .sum_vars) {
        s <- rowSums(shp); s[s <= 0] <- NA_real_
        shp / ifelse(is.na(s), 1, s) * tval
      } else {
        r <- rowMeans(shp); r[r <= 0] <- 1
        shp / r * tval
      }
    } else {
      shp + tval
    }
    ## impose physical bounds while keeping the daily aggregate intact
    b <- .met_bounds[[v]]
    if (!is.null(b))
      val <- .clamp_conserving(val, target = tval, lo = b[1], hi = b[2],
                               sum_type = v %in% .sum_vars)
    out[[v]] <- as.numeric(t(val))
  }

  ## ---- shortwave from solar geometry ---------------------------------
  if (swr_clear) {
    sw <- estimate_hourly_swr(
      data.frame(Date = tgt_days, MET_radswd = daily$MET_radswd),
      lat = lat, lon = lon, tz = tz, timestep = timestep, interval = interval)
    out$MET_radswd <- sw$MET_radswd
    say("shortwave rebuilt from solar geometry")
  }

  ## ---- wind direction ----------------------------------------------
  if ("MET_wnddir" %in% vars) {
    if (wind_uv && all(c("MET_wnduvu", "MET_wnduvv") %in% names(out))) {
      out$MET_wnddir <- (270 - atan2(out$MET_wnduvv, out$MET_wnduvu) *
                         180 / pi) %% 360
      say("MET_wnddir derived from the disaggregated u/v components")
    } else {
      out$MET_wnddir <- rep(daily$MET_wnddir %% 360, each = n_sub)
      say("MET_wnddir held constant through each day (circular; not shaped)")
    }
  }
  ## speed from the disaggregated vector components
  if (wind_uv && "MET_wndspd" %in% vars) {
    out$MET_wndspd <- sqrt(out$MET_wnduvu^2 + out$MET_wnduvv^2)
    say("MET_wndspd derived from the disaggregated u/v components ",
        "(daily scalar-mean speed is not conserved - see ?disaggregate_met_to_hourly)")
  }

  out <- out[, c("Date", vars), drop = FALSE]
  rownames(out) <- NULL
  attr(out, "tz") <- tz
  attr(out, "lat") <- lat; attr(out, "lon") <- lon
  attr(out, "method") <- method
  attr(out, "timestep") <- timestep
  if (method == "fragments" && length(donor_vars))
    attr(out, "donor_days") <- dm$days[pick]

  if (isTRUE(expand)) {
    if (is.null(lat) || is.null(lon))
      stop("expand = TRUE needs 'lat' and 'lon'.")
    keep <- attributes(out)[c("tz", "lat", "lon", "method", "timestep")]
    out <- expand_met(out, lat = lat, lon = lon, elev = elev, tz = tz)
    for (a in names(keep)) attr(out, a) <- keep[[a]]
  }
  out
}
