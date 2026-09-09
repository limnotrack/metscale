# Quick-look plot of an ERA5 / ERA5-Land GRIB or netCDF file

A fast visual check of a downloaded reanalysis file, drawn straight from
whatever is on disk. For every variable found in the file(s) it draws a
map of the field aggregated over time next to a time series - the
spatial mean over the whole grid, or a bilinear sample at `point`. Use
it to eyeball the footprint, the value range and the temporal coverage
before handing the file to
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
/
[`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md).

## Usage

``` r
plot_era5(
  file,
  var = NULL,
  time = NULL,
  fun = c("mean", "sum", "min", "max", "sd", "median"),
  point = NULL,
  engine = c("base", "ggplot2"),
  col = "viridis",
  max_vars = 6L,
  verbose = TRUE
)
```

## Arguments

- file:

  path to an ERA5 / ERA5-Land file (netCDF or GRIB). A vector of paths
  is allowed and is stacked in time, per variable.

- var:

  optional character vector selecting which variable(s) to draw, matched
  case-insensitively against the ERA5 short name / GRIB element (e.g.
  `"t2m"`, `"2T"`, `"tp"`). `NULL` (default) draws every variable in the
  file, capped at `max_vars`.

- time:

  which slice to map. `NULL` (default) aggregates every step with `fun`;
  otherwise a single step given as a `POSIXct` / `Date`, a
  `"YYYY-MM-DD HH:MM"` string (nearest step is used), or an integer
  layer index (negative counts from the end).

- fun:

  aggregation for the map when `time = NULL`: one of `"mean"` (default),
  `"sum"`, `"min"`, `"max"`, `"sd"`, `"median"`.

- point:

  optional `c(lon, lat)` in decimal degrees (WGS84). When given, the
  time-series panel is a bilinear sample at that point and the point is
  marked on the map; otherwise the series is the grid mean.

- engine:

  `"base"` (default) draws with
  [`terra::plot()`](https://rspatial.github.io/terra/reference/plot.html)
  and base graphics and returns the summary invisibly; `"ggplot2"`
  returns a faceted `ggplot` of the map(s) (single variable - it takes
  the first when several are present) and falls back to `"base"` when
  ggplot2 is not installed.

- col:

  a vector of colours for the map, or the name of an
  [`grDevices::hcl.colors()`](https://rdrr.io/r/grDevices/palettes.html)
  palette. Default `"viridis"`.

- max_vars:

  maximum number of variables to draw (default `6`).

- verbose:

  print a one-line summary per variable.

## Value

For `engine = "base"`, invisibly a data frame with one row per drawn
variable: `variable`, `label`, `units`, `n_layers`, `t_start`, `t_end`,
`xmin` / `xmax` / `ymin` / `ymax`, `res_x` / `res_y` and `min` / `mean`
/ `max` of the mapped field. The per-variable time series are attached
as `attr(., "series")` (a named list of `data.frame(time, value)`) and
the aggregated maps as `attr(., "maps")` (a named list of `SpatRaster`).
For `engine = "ggplot2"`, the `ggplot` object carrying the same
attributes.

## Details

The reader backend is chosen from the file extension, matching the
extractors: `.grib` / `.grb` / `.grib2` and everything else are all read
with terra. GRIB bands are grouped into variables by their
`GRIB_ELEMENT` metadata; netCDF files by sub-dataset / variable name.
Note that terra sometimes mislabels ERA5 GRIB units (e.g. reporting `K`
values under a `C` tag); the numbers are drawn as stored.

## See also

[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md),
[`plot_extract_grid()`](http://limnotrack.com/metscale/reference/plot_extract_grid.md),
[`read_era5_grib_point()`](http://limnotrack.com/metscale/reference/read_era5_grib_point.md)

## Examples

``` r
if (FALSE) { # \dontrun{
f <- system.file(
  "extdata/era5/reanalysis-era5-land_2m_temperature_hourly_2024_1_toba.grib",
  package = "metscale")

plot_era5(f)                            # map of the monthly mean + grid-mean series
plot_era5(f, point = c(98.6, 2.6))      # series sampled at a point
plot_era5(f, time = "2024-01-15 12:00") # one hour, mapped

## a directory of monthly files for one variable, stacked
plot_era5(list.files("era5_land", "2m_temperature.*\\.grib$", full.names = TRUE))
} # }
```
