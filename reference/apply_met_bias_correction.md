# Apply a fitted ERA5 met bias correction to a full record

Takes the object from
[`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md)
and applies it to any ERA5 met frame from
[`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
/
[`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md) -
typically the full record, not just the training window. Each corrected
variable is clamped back to physical bounds. Optionally the corrected
primaries are expanded so the dependent variables (dew point, vapour
pressure, cloud cover, longwave, u/v wind, station pressure) are
regenerated consistently with
[`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md).

## Usage

``` r
apply_met_bias_correction(
  era5,
  bc,
  vars = NULL,
  clamp = TRUE,
  swr_ceiling = 1361,
  expand = FALSE,
  lat = NULL,
  lon = NULL,
  elev = NULL,
  tz = NULL,
  verbose = TRUE
)
```

## Arguments

- era5:

  data frame with `Date` + `MET_*` columns.

- bc:

  a `met_biascorr` object from
  [`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md).

- vars:

  subset of `names(bc$models)` to apply; default all.

- clamp:

  clamp to physical bounds after correcting (default `TRUE`):
  `MET_pprain`/`MET_ppsnow`/`MET_radswd`/`MET_radlwd`/`MET_wndspd` \>=
  0, `MET_humrel` within 0 to 100, `MET_radswd` \<= `swr_ceiling`.

- swr_ceiling:

  hard upper bound for corrected `MET_radswd` (W/m2). Default 1361
  (solar constant); pass a clear-sky series (same length as `era5`) for
  a tighter, time-varying cap.

- expand:

  if `TRUE`, keep `Date` + corrected primaries and call
  [`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
  to rebuild the full set. Needs `lat`/`lon`/`elev` (taken from
  `attr(era5, "lat")` / `"lon"` when `NULL`).

- lat, lon, elev:

  lake position for `expand`.

- tz:

  timezone for the solar geometry in
  [`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md);
  defaults to the `tz` attribute of `era5`, else `"Etc/GMT-12"`.

- verbose:

  report which variables were corrected.

## Value

`era5` with corrected columns (same class/attributes), plus
`attr(., "biascorr")` recording the training window and methods. When
`expand = TRUE`, the
[`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
output frame.

## See also

[`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md),
[`met_to_daily()`](http://limnotrack.com/climprep/reference/met_to_daily.md),
[`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
