#' ERA5 reference table
#'
#' A reference table mapping meteorological variable names, units and daily
#' aggregation functions between ERA5, LakeEnsemblR (LER) and AEME.
#'
#' @format ## `era5_ref_table`
#' A data frame with 10 rows and 7 columns:
#' \describe{
#'   \item{variable}{Human-readable variable name}
#'   \item{era5}{ERA5 (CDS) variable name}
#'   \item{nc}{ERA5 netCDF short name}
#'   \item{ler}{LakeEnsemblR variable name}
#'   \item{aeme}{AEME `MET_*` variable name}
#'   \item{nc_unit}{Units of the raw ERA5 netCDF variable}
#'   \item{agg_fun}{Function used to aggregate hourly values to daily}
#' }
#' @source Package development.
"era5_ref_table"
