## ===========================================================================
## Precompile the heavy vignettes.
##
## `scenario-workflow` runs a full bias-correction + delta-change +
## disaggregation pipeline - far too slow for R CMD check / CRAN. It is
## PRECOMPUTED here: this script runs it once and bakes the code, output and
## figures into `vignettes/scenario-workflow.Rmd`, which ships as a static
## document with no live `{r}` chunks.
##
## Run from the package root:
##
##   Rscript data-raw/precompile_vignettes.R
##
## Then commit `vignettes/scenario-workflow.Rmd` and
## `vignettes/scenario-workflow-*.png`.
## ===========================================================================

suppressWarnings(suppressMessages(
  devtools::load_all(".", quiet = TRUE)
))
stopifnot(requireNamespace("knitr", quietly = TRUE))

root <- normalizePath(".", mustWork = TRUE)
vig  <- file.path(root, "vignettes")
stopifnot(file.exists(file.path(vig, "scenario-workflow.Rmd.orig")))

## knit from inside vignettes/ so `fig.path` writes there; `system.file()`
## used by the vignette is working-directory-independent.
setwd(vig)
knitr::knit("scenario-workflow.Rmd.orig", output = "scenario-workflow.Rmd",
            quiet = TRUE)
setwd(root)

## normalise to LF so the committed file is stable across platforms
f <- file.path(vig, "scenario-workflow.Rmd")
lines <- readLines(f)
con <- file(f, "wb"); writeLines(lines, con, sep = "\n"); close(con)

message("wrote vignettes/scenario-workflow.Rmd")
figs <- list.files(vig, pattern = "^scenario-workflow-.*\\.png$")
message("figures: ", paste(figs, collapse = ", "))
message("sizes (KB): ",
        paste(round(file.info(file.path(vig, figs))$size / 1024), collapse = " "))
