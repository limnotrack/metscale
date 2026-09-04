#' @keywords internal
"_PACKAGE"

## Shared internal helper. `.mbc_predict()` lives in fit_met_bias_correction.R.

#' NULL / empty coalescing operator
#' @noRd
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
