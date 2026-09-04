# ERA5 reference table

A reference table mapping meteorological variable names, units and daily
aggregation functions between ERA5, LakeEnsemblR (LER) and AEME.

## Usage

``` r
era5_ref_table
```

## Format

### `era5_ref_table`

A data frame with 10 rows and 7 columns:

- variable:

  Human-readable variable name

- era5:

  ERA5 (CDS) variable name

- nc:

  ERA5 netCDF short name

- ler:

  LakeEnsemblR variable name

- aeme:

  AEME `MET_*` variable name

- nc_unit:

  Units of the raw ERA5 netCDF variable

- agg_fun:

  Function used to aggregate hourly values to daily

## Source

Package development.
