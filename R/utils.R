#' Round to a multiple of an arbitrary accuracy
#'
#' @param x numeric vector to round.
#' @param accuracy numeric; the multiple to round to.
#' @param f rounding function to apply (`round`, `floor` or `ceiling`).
#' @return `x` rounded to the nearest multiple of `accuracy`.
#' @noRd
round_any <- function(x, accuracy, f = round) f(x / accuracy) * accuracy
