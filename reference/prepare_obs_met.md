# Standardise a table of locally measured meteorology for bias correction

Takes a user-supplied observation table (lake buoy, shore weather
station, council / NIWA / CliFlo export, logger dump) and returns a
clean data frame with a `Date` column and AEME `MET_*` columns in AEME
units, resampled to the resolution you intend to bias-correct at. The
output is designed to line up with
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
output so the two can be joined on `Date` in
[`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md).

## Usage

``` r
prepare_obs_met(
  obs,
  col_map = NULL,
  datetime_col = NULL,
  date_format = NULL,
  tz = "Etc/GMT-12",
  resample = c("none", "hour", "day"),
  interval = c("ending", "beginning"),
  derive = TRUE,
  convert_units = TRUE,
  wind_height = NULL,
  wind_z0 = 2e-04,
  station = NA_character_,
  verbose = TRUE
)
```

## Arguments

- obs:

  data frame, or path to a `.csv` / `.rds` file.

- col_map:

  optional named character vector mapping AEME names to the columns in
  `obs`, e.g.
  `c(MET_tmpair = "AirTemp_C", MET_wndspd = "WindSpd", MET_radswd = "SolarRad")`.
  Columns not listed are dropped. If `NULL`, columns already named
  `MET_*` are kept and the rest are matched with
  [`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md).

- datetime_col:

  name of the timestamp column; auto-detected when `NULL` (first column
  named or containing `date`/`time`).

- date_format:

  optional `strptime` format string for the timestamp column. When
  `NULL` (default) a set of common formats is tried; if the strings
  contain a time (a `:`), only date-time formats are considered so that
  a stray time-less row does not silently collapse the whole column to
  dates.

- tz:

  time zone of the observation timestamps. Default `"Etc/GMT-12"` =
  fixed NZST (matches the extractor default). Use `"Pacific/Auckland"`
  if the logger recorded civil time with DST.

- resample:

  `"none"` (keep native step, de-duplicated), `"hour"` (mean per hour;
  rain/snow summed) or `"day"` (daily mean; rain/snow summed; `Date`
  returned as class `Date`).

- interval:

  which hour a sub-hourly record belongs to when `resample = "hour"`.
  `"ending"` (default) puts a record at 00:15 into the hour labelled
  01:00, matching the accumulated-flux convention of ERA5 and
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md),
  so the two line up when joined; `"beginning"` labels it 00:00. With
  `"ending"` the first bin of a record that starts exactly on the hour
  holds a single observation. Ignored for `resample = "day"`, which
  always uses calendar days.

- derive:

  if `TRUE` (default) fill `MET_wndspd`/`MET_wnddir` from u/v (or vice
  versa) and `MET_tmpdew`\<-\>`MET_humrel` from air temperature, where
  the inputs are present.

- convert_units:

  if `TRUE` (default) auto-detect and fix common unit mistakes
  (K-\>degC, hPa-\>Pa, RH 0-1 -\> %, km/h-\>m/s, mm-\>... ).

- wind_height:

  measurement height of the wind sensor, m. When given and not already
  10, the wind columns are rescaled to 10 m (the ERA5 / lake-model
  convention) with
  [`met_wind_at_height()`](http://limnotrack.com/metscale/reference/met_wind_at_height.md) -
  a buoy anemometer at 2 m needs `wind_height = 2`. `NULL` (default)
  leaves wind untouched.

- wind_z0:

  roughness length (m) for that adjustment; default `2e-4` (open water).
  See
  [`wind_at_height()`](http://limnotrack.com/metscale/reference/wind_at_height.md).

- station:

  optional label stored on the result (`"buoy"`, `"shore"`, station
  id) - carried into the bias-correction metadata.

- verbose:

  print what was matched / converted / resampled.

## Value

data frame, `Date` first, then the matched `MET_*` columns. Attributes:
`tz`, `resolution` (`"subhourly"`/`"hourly"`/`"daily"`), `station`,
`n_obs`.

## Details

Standard names / units (see
[`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md)):
`MET_tmpair` degC, `MET_tmpdew` degC, `MET_humrel` %, `MET_wndspd` m/s,
`MET_wnddir` deg (FROM), `MET_wnduvu`/`MET_wnduvv` m/s, `MET_radswd` and
`MET_radlwd` W/m2, `MET_pprain`/`MET_ppsnow` mm (per timestep),
`MET_prsttn`/`MET_prmslp` Pa.

## See also

[`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md),
[`apply_met_bias_correction()`](http://limnotrack.com/metscale/reference/apply_met_bias_correction.md)
