#' Standardise a table of locally measured meteorology for bias correction
#'
#' Takes a user-supplied observation table (lake buoy, shore weather
#' station, council / NIWA / CliFlo export, logger dump) and returns a
#' clean data frame with a `Date` column and AEME `MET_*` columns in AEME
#' units, resampled to the resolution you intend to bias-correct at. The
#' output is designed to line up with [extract_era5_hourly_met()] output so
#' the two can be joined on `Date` in [fit_met_bias_correction()].
#'
#' Standard names / units (see [met_vars()]):
#' `MET_tmpair` degC, `MET_tmpdew` degC, `MET_humrel` %, `MET_wndspd` m/s,
#' `MET_wnddir` deg (FROM), `MET_wnduvu`/`MET_wnduvv` m/s, `MET_radswd` and
#' `MET_radlwd` W/m2, `MET_pprain`/`MET_ppsnow` mm (per timestep),
#' `MET_prsttn`/`MET_prmslp` Pa.
#'
#' @param obs data frame, or path to a `.csv` / `.rds` file.
#' @param col_map optional named character vector mapping AEME names to the
#'   columns in `obs`, e.g.
#'   `c(MET_tmpair = "AirTemp_C", MET_wndspd = "WindSpd", MET_radswd = "SolarRad")`.
#'   Columns not listed are dropped. If `NULL`, columns already named
#'   `MET_*` are kept and the rest are matched with [guess_met_vars()].
#' @param datetime_col name of the timestamp column; auto-detected when
#'   `NULL` (first column named or containing `date`/`time`).
#' @param date_format optional `strptime` format string for the timestamp
#'   column. When `NULL` (default) a set of common formats is tried; if the
#'   strings contain a time (a `:`), only date-time formats are considered
#'   so that a stray time-less row does not silently collapse the whole
#'   column to dates.
#' @param tz time zone of the observation timestamps. Default
#'   `"Etc/GMT-12"` = fixed NZST (matches the extractor default). Use
#'   `"Pacific/Auckland"` if the logger recorded civil time with DST.
#' @param resample `"none"` (keep native step, de-duplicated), `"hour"`
#'   (mean per hour; rain/snow summed) or `"day"` (daily mean; rain/snow
#'   summed; `Date` returned as class `Date`).
#' @param interval which hour a sub-hourly record belongs to when
#'   `resample = "hour"`. `"ending"` (default) puts a record at 00:15 into
#'   the hour labelled 01:00, matching the accumulated-flux convention of
#'   ERA5 and [extract_era5_hourly_met()], so the two line up when joined;
#'   `"beginning"` labels it 00:00. With `"ending"` the first bin of a
#'   record that starts exactly on the hour holds a single observation.
#'   Ignored for `resample = "day"`, which always uses calendar days.
#' @param derive if `TRUE` (default) fill `MET_wndspd`/`MET_wnddir` from
#'   u/v (or vice versa) and `MET_tmpdew`<->`MET_humrel` from air
#'   temperature, where the inputs are present.
#' @param convert_units if `TRUE` (default) auto-detect and fix common unit
#'   mistakes (K->degC, hPa->Pa, RH 0-1 -> %, km/h->m/s, mm->... ).
#' @param wind_height measurement height of the wind sensor, m. When given
#'   and not already 10, the wind columns are rescaled to 10 m (the ERA5 /
#'   lake-model convention) with [met_wind_at_height()] - a buoy anemometer
#'   at 2 m needs `wind_height = 2`. `NULL` (default) leaves wind untouched.
#' @param wind_z0 roughness length (m) for that adjustment; default `2e-4`
#'   (open water). See [wind_at_height()].
#' @param station optional label stored on the result (`"buoy"`,
#'   `"shore"`, station id) - carried into the bias-correction metadata.
#' @param verbose print what was matched / converted / resampled.
#'
#' @return data frame, `Date` first, then the matched `MET_*` columns.
#'   Attributes: `tz`, `resolution` (`"subhourly"`/`"hourly"`/`"daily"`),
#'   `station`, `n_obs`.
#'
#' @seealso [fit_met_bias_correction()], [apply_met_bias_correction()]
#' @export
prepare_obs_met <- function(obs,
                            col_map = NULL,
                            datetime_col = NULL,
                            date_format = NULL,
                            tz = "Etc/GMT-12",
                            resample = c("none", "hour", "day"),
                            interval = c("ending", "beginning"),
                            derive = TRUE,
                            convert_units = TRUE,
                            wind_height = NULL,
                            wind_z0 = 2e-4,
                            station = NA_character_,
                            verbose = TRUE) {

  resample <- match.arg(resample)
  interval <- match.arg(interval)
  say <- function(...) if (isTRUE(verbose)) message(...)

  if (is.character(obs) && length(obs) == 1L && file.exists(obs)) {
    obs <- if (grepl("\\.rds$", obs, ignore.case = TRUE)) readRDS(obs)
           else utils::read.csv(obs, stringsAsFactors = FALSE, check.names = FALSE)
  }
  obs <- as.data.frame(obs, check.names = FALSE)
  if (!nrow(obs)) stop("'obs' has no rows.")

  ## ---- timestamp -----------------------------------------------------
  if (is.null(datetime_col)) {
    cand <- names(obs)[tolower(names(obs)) %in%
                         c("date", "datetime", "time", "timestamp", "dt")]
    if (!length(cand))
      cand <- names(obs)[grepl("date|time", names(obs), ignore.case = TRUE)]
    if (!length(cand)) stop("Could not find a date/time column; set 'datetime_col'.")
    datetime_col <- cand[1]
  }
  say("Timestamp column: ", datetime_col)
  tv <- obs[[datetime_col]]
  if (inherits(tv, c("POSIXct", "POSIXlt"))) {
    Date <- as.POSIXct(as.numeric(tv), origin = "1970-01-01", tz = tz)
  } else if (inherits(tv, "Date")) {
    Date <- as.POSIXct(format(tv), tz = tz)
  } else {
    tv <- trimws(as.character(tv))
    tv[tv == "" | tv %in% c("NA", "NaN")] <- NA_character_

    ## Pick ONE format - the one that parses the most rows - rather than
    ## letting base::tryFormats fall through to a date-only format the
    ## moment a single row fails (the usual cause of hourly obs coming out
    ## daily). Rows that carry a time but end up on a date-only format are
    ## re-parsed with the matching date-time format.
    pick_format <- function(x, cand) {
      hit <- vapply(cand, function(f) sum(!is.na(
        as.POSIXct(x, tz = tz, format = f))), integer(1))
      cand[which.max(hit)]
    }
    dt_fmts <- c("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%dT%H:%M:%S",
                 "%Y/%m/%d %H:%M:%S", "%Y/%m/%d %H:%M",
                 "%d/%m/%Y %H:%M:%S", "%d/%m/%Y %H:%M",
                 "%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%Y%m%d %H:%M:%S")
    d_fmts  <- c("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%Y%m%d")

    if (!is.null(date_format)) {
      Date <- as.POSIXct(tv, tz = tz, format = date_format)
    } else {
      has_t <- grepl("[0-9]:[0-9]", tv) & !is.na(tv)
      Date  <- as.POSIXct(rep(NA_real_, length(tv)), tz = tz)
      if (any(has_t)) {
        f <- pick_format(tv[has_t], dt_fmts)
        Date[has_t] <- as.POSIXct(tv[has_t], tz = tz, format = f)
      }
      if (any(!has_t & !is.na(tv))) {
        i <- !has_t & !is.na(tv)
        f <- pick_format(tv[i], d_fmts)
        Date[i] <- as.POSIXct(tv[i], tz = tz, format = f)
      }
    }
    nfail <- sum(is.na(Date) & !is.na(tv))
    if (nfail > 0)
      say(nfail, " timestamp(s) could not be parsed",
          if (is.null(date_format)) " - pass 'date_format'" else
            paste0(" with '", date_format, "'"), " and were dropped")
  }
  if (all(is.na(Date))) stop("Failed to parse '", datetime_col, "' as date/time.")

  ## ---- column matching --------------------------------------------------
  aeme_names <- c("MET_radswd", "MET_radlwd", "MET_cldcvr", "MET_tmpair",
                  "MET_humrel", "MET_tmpdew", "MET_prvapr", "MET_prsttn",
                  "MET_prmslp", "MET_wndspd", "MET_wnddir", "MET_wnduvu",
                  "MET_wnduvv", "MET_pprain", "MET_ppsnow")
  if (!is.null(col_map)) {
    bad <- setdiff(unname(col_map), names(obs))
    if (length(bad)) stop("col_map points at missing column(s): ",
                          paste(bad, collapse = ", "))
    dat <- as.data.frame(obs[, unname(col_map), drop = FALSE])
    names(dat) <- names(col_map)
  } else {
    keep <- intersect(names(obs), aeme_names)
    rest <- setdiff(names(obs), c(keep, datetime_col))
    guess <- character(0)
    if (length(rest)) {
      g <- guess_met_vars(rest)
      g[g %in% keep] <- NA_character_          # already present under its own name
      names(g) <- rest
      guess <- g[!is.na(g) & !duplicated(g)]
    }
    if (!length(keep) && !length(guess))
      stop("No meteorological columns matched. Pass an explicit 'col_map'.")
    dat <- as.data.frame(obs[, c(keep, names(guess)), drop = FALSE])
    names(dat) <- c(keep, unname(guess))
    if (length(guess))
      say("Matched: ", paste(sprintf("%s->%s", names(guess), guess), collapse = ", "))
  }
  dat[] <- lapply(dat, function(x) suppressWarnings(as.numeric(x)))
  out <- data.frame(Date = Date, dat, check.names = FALSE)
  out <- out[!is.na(out$Date), , drop = FALSE]
  out <- out[order(out$Date), , drop = FALSE]
  ndup <- sum(duplicated(out$Date))
  if (ndup > 0 && ndup >= 0.1 * nrow(out))
    warning(ndup, " of ", nrow(out), " rows share a timestamp and were ",
            "dropped - the timestamp column probably parsed without its ",
            "time-of-day. Check 'date_format'.")
  out <- out[!duplicated(out$Date), , drop = FALSE]

  ## ---- unit fixes (hourly-safe: use non-zero medians) ----------------
  nzmed <- function(x) { v <- x[is.finite(x) & x != 0]; if (!length(v)) NA_real_ else stats::median(v) }
  if (isTRUE(convert_units)) {
    for (v in intersect(c("MET_tmpair", "MET_tmpdew"), names(out)))
      if (isTRUE(nzmed(out[[v]]) > 100)) { out[[v]] <- out[[v]] - 273.15; say(v, ": K -> degC") }
    for (v in intersect(c("MET_prsttn", "MET_prmslp"), names(out)))
      if (isTRUE(nzmed(out[[v]]) < 2000)) { out[[v]] <- out[[v]] * 100; say(v, ": hPa -> Pa") }
    if ("MET_humrel" %in% names(out) && isTRUE(max(out$MET_humrel, na.rm = TRUE) <= 1.5)) {
      out$MET_humrel <- out$MET_humrel * 100; say("MET_humrel: fraction -> %")
    }
    for (v in intersect(c("MET_wndspd", "MET_wnduvu", "MET_wnduvv"), names(out))) {
      m <- abs(nzmed(out[[v]]))
      if (isTRUE(m > 35)) { out[[v]] <- out[[v]] / 3.6; say(v, ": km/h -> m/s") }
      else if (isTRUE(m > 25 && m <= 35)) say(v, ": median in km/h/knots grey zone - check units")
    }
    for (v in intersect(c("MET_pprain", "MET_ppsnow"), names(out))) {
      mx <- suppressWarnings(max(out[[v]], na.rm = TRUE))
      if (is.finite(mx) && mx > 0 && mx < 0.05) { out[[v]] <- out[[v]] * 1000; say(v, ": m -> mm") }
    }
    if ("MET_cldcvr" %in% names(out) && isTRUE(max(out$MET_cldcvr, na.rm = TRUE) > 1.5)) {
      out$MET_cldcvr <- out$MET_cldcvr / 8; say("MET_cldcvr: oktas -> fraction")
    }
  }

  ## ---- derive missing wind / humidity pairs --------------------------
  if (isTRUE(derive)) {
    hasc <- function(...) all(c(...) %in% names(out))
    if (hasc("MET_wnduvu", "MET_wnduvv") && !"MET_wndspd" %in% names(out)) {
      out$MET_wndspd <- sqrt(out$MET_wnduvu^2 + out$MET_wnduvv^2)
      out$MET_wnddir <- (270 - atan2(out$MET_wnduvv, out$MET_wnduvu) * 180 / pi) %% 360
      say("Derived MET_wndspd / MET_wnddir from u,v")
    }
    if (hasc("MET_wndspd", "MET_wnddir") && !"MET_wnduvu" %in% names(out)) {
      rad <- out$MET_wnddir * pi / 180
      out$MET_wnduvu <- -out$MET_wndspd * sin(rad)
      out$MET_wnduvv <- -out$MET_wndspd * cos(rad)
      say("Derived MET_wnduvu / MET_wnduvv from speed,dir")
    }
    if (hasc("MET_tmpair", "MET_humrel") && !"MET_tmpdew" %in% names(out)) {
      a <- log(pmin(pmax(out$MET_humrel, 1e-3), 100) / 100) +
        (17.625 * out$MET_tmpair) / (243.04 + out$MET_tmpair)
      out$MET_tmpdew <- (243.04 * a) / (17.625 - a)
      say("Derived MET_tmpdew from air temp + RH")
    }
    if (hasc("MET_tmpair", "MET_tmpdew") && !"MET_humrel" %in% names(out)) {
      out$MET_humrel <- pmin(100, 100 * exp(17.625 * out$MET_tmpdew / (243.04 + out$MET_tmpdew)) /
                               exp(17.625 * out$MET_tmpair / (243.04 + out$MET_tmpair)))
      say("Derived MET_humrel from air temp + dew point")
    }
  }

  ## ---- adjust wind to the 10 m convention ---------------------------
  if (!is.null(wind_height) && isTRUE(as.numeric(wind_height) != 10) &&
      any(c("MET_wndspd", "MET_wnduvu", "MET_wnduvv") %in% names(out))) {
    out <- met_wind_at_height(out, from = as.numeric(wind_height), to = 10,
                              z0 = wind_z0)
    say("Adjusted wind ", wind_height, " m -> 10 m (neutral log profile, z0 = ",
        wind_z0, " m)")
  }

  ## ---- resolution / resampling -------------------------------------
  step_h <- stats::median(as.numeric(diff(out$Date), units = "hours"), na.rm = TRUE)
  native <- if (is.na(step_h)) "unknown" else if (step_h < 0.98) "subhourly" else
            if (step_h < 23) "hourly" else "daily"
  sum_vars <- intersect(c("MET_pprain", "MET_ppsnow"), names(out))
  vcols <- setdiff(names(out), "Date")

  agg <- function(df, key) {
    g <- split(seq_len(nrow(df)), key)
    res <- lapply(names(g), function(k) {
      idx <- g[[k]]
      row <- lapply(vcols, function(v) {
        x <- df[[v]][idx]
        if (all(is.na(x))) NA_real_
        else if (v %in% sum_vars) sum(x, na.rm = TRUE)
        else mean(x, na.rm = TRUE)
      })
      stats::setNames(row, vcols)
    })
    cbind(data.frame(.key = names(g)), do.call(rbind, lapply(res, as.data.frame)))
  }

  if (resample == "hour" && native == "subhourly") {
    ## bin to whole hours; a record exactly on the hour belongs to that hour
    ## under either convention
    secs <- as.numeric(out$Date)
    bin  <- if (interval == "ending") ceiling(secs / 3600) * 3600
            else                      floor(secs / 3600) * 3600
    a <- agg(out, as.character(bin))
    out <- data.frame(Date = as.POSIXct(as.numeric(a$.key),
                                        origin = "1970-01-01", tz = tz),
                      a[vcols], check.names = FALSE)
    resolution <- "hourly"
    say("Resampled sub-hourly -> hourly, ", interval, "-labelled (",
        nrow(out), " rows)")
  } else if (resample == "day") {
    key <- as.character(as.Date(out$Date, tz = tz))
    a <- agg(out, key)
    out <- data.frame(Date = as.Date(a$.key), a[vcols], check.names = FALSE)
    resolution <- "daily"
    say("Resampled -> daily (", nrow(out), " rows)")
  } else {
    resolution <- native
  }
  out <- out[order(out$Date), , drop = FALSE]
  rownames(out) <- NULL

  attr(out, "tz") <- tz
  attr(out, "resolution") <- resolution
  attr(out, "station") <- station
  attr(out, "n_obs") <- nrow(out)
  out
}
