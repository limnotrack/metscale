# Fit a bias correction for ERA5-Land meteorology from local observations

Joins an ERA5 met frame (from
[`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
/
[`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md))
to a matching frame of locally measured meteorology (from
[`prepare_obs_met()`](http://limnotrack.com/climprep/reference/prepare_obs_met.md))
over their common period and fits, per variable, a transfer function
that maps ERA5 onto the observations. The fitted object is applied to
the full ERA5 record with
[`apply_met_bias_correction()`](http://limnotrack.com/climprep/reference/apply_met_bias_correction.md).

## Usage

``` r
fit_met_bias_correction(
  era5,
  obs,
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
  verbose = TRUE
)
```

## Arguments

- era5:

  data frame with `Date` plus `MET_*` columns (extractor output).

- obs:

  data frame with `Date` plus `MET_*` columns
  ([`prepare_obs_met()`](http://limnotrack.com/climprep/reference/prepare_obs_met.md)
  output). Must be the same resolution and time zone as `era5`.

- vars:

  character vector of `MET_*` columns to correct. `NULL` (default) uses
  the columns common to both, excluding derived/direction fields
  (`MET_wnddir`, `MET_wnduvu`, `MET_wnduvv`, `MET_cldcvr`, `MET_prvapr`,
  `MET_prmslp`).

- method:

  `"scale"` (default), `"variance"`, `"linear"`, `"eqm"` or `"qdm"`; or
  a named vector, e.g. `c(MET_wndspd = "eqm", MET_tmpair = "scale")`.

- transform:

  `"auto"` (ratio for `MET_wndspd`/`MET_radswd`/
  `MET_pprain`/`MET_ppsnow`, additive otherwise), `"additive"` or
  `"ratio"`; or a named vector. Only used by `method = "scale"`.

- by:

  `"doy-loess"` (default), `"month"` or `"none"`. Coerced to `"month"`
  for methods other than `"scale"`.

- cv:

  `"loyo"` (leave-one-year-out, default) or `"none"` - controls whether
  the skill table includes out-of-sample rows.

- min_n:

  minimum paired records per monthly stratum (default 60).

- cv_min_months:

  a year is usable as a leave-one-out fold only if it has at least this
  many months of overlap (default 8).

- loess_span:

  span for the day-of-year loess (default 0.25).

- robust:

  use [`MASS::rlm`](https://rdrr.io/pkg/MASS/man/rlm.html) for
  `method = "linear"` (default `FALSE`).

- nquantiles:

  number of quantiles for `"eqm"`/`"qdm"` (default 50).

- swr_daytime_wm2:

  ERA5 shortwave threshold (W/m2) above which a record counts as daytime
  for the shortwave fit (default 5).

- verbose:

  print progress and the skill table.

## Value

an object of class `met_biascorr`: a list with `models` (per variable),
`skill` (data frame: `variable`, `stage` in
`raw`/`corrected`/`cv_raw`/`cv_corrected`, `n`, `bias`, `mae`, `rmse`,
`r`, `kge`), `training` (window, resolution, tz, years, station) and
`call`.

## Details

Methods (set globally via `method`, or per variable with a named
vector):

- `"scale"`:

  (default) a per-month offset - additive (`obs - era5`) or
  multiplicative (`sum(obs) / sum(era5)`), chosen by `transform`. With
  `by = "doy-loess"` the 12 monthly offsets are loess-smoothed across
  the day-of-year (as `nz_climate_projections/climate_shift.R`).

- `"variance"`:

  per-month mean and standard-deviation matching:
  `mean_o + (x - mean_e) * sd_o / sd_e`.

- `"linear"`:

  per-month least squares `obs ~ a + b * era5` (`robust = TRUE` uses
  [`MASS::rlm`](https://rdrr.io/pkg/MASS/man/rlm.html)).

- `"eqm"`:

  empirical quantile mapping per month - remap the ERA5 CDF onto the
  observed CDF, linear interpolation, constant-tail extrapolation.

- `"qdm"`:

  quantile delta mapping - as `"eqm"` but preserves the ERA5 anomaly
  relative to its training quantile, so trends/among-year signal survive
  extrapolation.

Any stratum with fewer than `min_n` pairs falls back to the pooled
(all-month) fit. Shortwave is fitted on daytime records only.

## See also

[`prepare_obs_met()`](http://limnotrack.com/climprep/reference/prepare_obs_met.md),
[`apply_met_bias_correction()`](http://limnotrack.com/climprep/reference/apply_met_bias_correction.md)
