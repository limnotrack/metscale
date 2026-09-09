# Convert downloaded ERA5 files to a daily meteorology data frame

Convenience wrapper that runs
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
over the ERA5 files in `path` (netCDF, or GRIB as written by
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md))
and aggregates the model-ready hourly frame to daily with
[`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md):
precipitation and snowfall are summed, everything else is averaged,
and - unless `minmax = FALSE` - daily minimum and maximum air and
dewpoint temperature are added.

File discovery (by name `pattern`), the per-file reader backend, spatial
sampling (`method`), de-accumulation of the flux variables, unit
conversion and the UTC -\> `tz` shift are all handled by
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md);
see there for the details and for the arguments passed through `...`.

## Usage

``` r
convert_era5_netcdf(
  path,
  format = c("AEME", "LER", "raw"),
  tz = "UTC",
  minmax = TRUE,
  min_frac = 0.5,
  site = NULL,
  outfile = NULL,
  ...
)
```

## Arguments

- path:

  directory holding the ERA5 files (netCDF or GRIB).

- format:

  `"AEME"` (default, `MET_*` names, a `Date` column), `"LER"`
  (LakeEnsemblR names) or `"raw"` (ERA5 short names); `"LER"` and
  `"raw"` return a `datetime` column.

- tz:

  output / aggregation time zone: passed to
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  and used to assign calendar days. Default `"UTC"`.

- minmax:

  add daily min / max columns for air and dewpoint temperature
  (`MET_airmin` / `MET_airmax` / `MET_dewmin` / `MET_dewmax` in AEME
  naming). Default `TRUE`.

- min_frac:

  drop days with fewer than this fraction of the expected hourly
  records, passed to
  [`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md).
  Default `0.5`; set `0` to keep every day.

- site:

  optional site tag; when given (and `pattern` is left at its default)
  only files whose name contains the tag are used - a shortcut for
  `pattern = paste0("*{variable}*", site, "*")`.

- outfile:

  optional path; if given the daily frame is written there with
  [`utils::write.csv()`](https://rdrr.io/r/utils/write.table.html)
  (`row.names = FALSE`, dates as `"%Y-%m-%d"`).

- ...:

  further arguments for
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md):
  `lon`, `lat`, `geom`, `years`, `months`, `variables`, `method`,
  `precip_units`, `pressure_units`, `pattern`, `max_dist_km`,
  `area_crs`, `fill_gaps`, `verbose`.

## Value

a daily data frame: the time column first, then one column per variable
in the chosen `format`, plus the temperature min / max columns when
`minmax = TRUE`. The `lon` / `lat` / `tz` / `method` attributes from
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
are carried through.

## See also

[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
for the hourly frame and the full argument list,
[`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md)
for the aggregation,
[`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md)
which recognises the `"raw"` ERA5 short names directly.

## Examples

``` r
if (FALSE) { # \dontrun{
lon <- 98.67591; lat <- 2.637047            # Lake Toba, Indonesia
met <- convert_era5_netcdf(
  path = "data/test", lon = lon, lat = lat, years = 2024,
  variables = "2m_temperature")
} # }
```
