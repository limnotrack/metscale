#' @keywords internal
"_PACKAGE"

## Shared internal helper. `.mbc_predict()` lives in fit_met_bias_correction.R.

#' NULL / empty coalescing operator
#' @noRd
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Resolve a timezone argument
#'
#' Returns the first usable value of: the explicit `tz` argument, then each
#' fallback in `...` (typically a data frame's `tz` attribute or a
#' POSIXct's `tzone`), then `"UTC"`. `NULL`, `NA` and `""` all count as
#' "not set" - `""` is R's marker for the session's local zone, which is
#' exactly what we do not want to depend on.
#' @noRd
.tz_or_utc <- function(tz, ...) {
  for (v in c(list(tz), list(...))) {
    if (!is.null(v) && length(v) == 1L && !is.na(v) && nzchar(v)) return(v)
  }
  "UTC"
}
