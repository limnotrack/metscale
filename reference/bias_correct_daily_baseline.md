# Build a bias-corrected daily baseline for a climate-scenario workflow

Applies a fitted
[`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md)
to a full hourly reanalysis record, aggregates to daily and regenerates
the dependent variables, so the result is ready to be handed to a
delta-change routine such as `AEME`'s `climate_shift()` as the baseline
meteorology.

## Usage

``` r
bias_correct_daily_baseline(
  era5,
  bc = NULL,
  lat = NULL,
  lon = NULL,
  elev = 0,
  tz = NULL,
  expand = TRUE,
  min_frac = 0.5,
  verbose = TRUE
)
```

## Arguments

- era5:

  hourly reanalysis met, from
  [`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md).

- bc:

  a `met_biascorr` from
  [`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md);
  `NULL` to aggregate without correcting.

- lat, lon, elev:

  lake position; taken from the attributes of `era5` when `NULL`.

- tz:

  timezone for day boundaries and solar geometry; defaults to the `tz`
  attribute of `era5`.

- expand:

  regenerate the dependent variables with
  [`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
  (default `TRUE`).

- min_frac:

  minimum fraction of a day that must be present for that day to be
  kept, passed to
  [`met_to_daily()`](http://limnotrack.com/climprep/reference/met_to_daily.md).

- verbose:

  print progress.

## Value

daily data frame with `Date` of class `Date` and `MET_*` columns,
carrying a `biascorr` attribute describing the correction.

## Details

The rainfall column is always populated from the corrected record, so
that downstream code which special-cases an all-zero `MET_pprain` (as
`climate_shift()` does, by substituting inflow-derived rainfall) does
not take that branch unintentionally.

## See also

[scenario_workflow](http://limnotrack.com/climprep/reference/scenario_workflow.md)
for the full delta-change pipeline and
[`vignette("scenario-workflow", package = "climprep")`](http://limnotrack.com/climprep/articles/scenario-workflow.md).

## Examples

``` r
if (FALSE) { # \dontrun{
era5 <- extract_era5_lake_met("LID 11133", path = nc_dir, lakes = lakes,
                              method = "area", years = 1980:2024)
obs  <- prepare_obs_met("obs/rotorua_buoy_met.csv", resample = "hour")
bc   <- fit_met_bias_correction(era5, obs)

baseline <- bias_correct_daily_baseline(era5, bc, elev = 279)

## hand to AEME's delta-change routine
inp <- AEME::input(aeme); inp$meteo <- baseline
AEME::input(aeme) <- inp
} # }
```
