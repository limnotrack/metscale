# Hourly ERA5-Land meteorology averaged over a lake polygon

Thin convenience wrapper around
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md):
it takes a single lake outline, defaults `method` to `"area"` (the
area-weighted mean of every overlapping ERA5 grid cell, best when a lake
straddles several cells) and tags the result with optional `id` / `name`
labels.

## Usage

``` r
extract_era5_lake_met(
  polygon,
  path,
  method = c("area", "area_mean", "bilinear", "nearest"),
  id = NULL,
  name = NULL,
  ...
)
```

## Arguments

- polygon:

  the lake outline: an `sf` / `sfc` polygon in any CRS, a path to a
  vector file
  [`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html)
  can open (`.gpkg`, `.shp`, ...), or a path to an `.rds` holding an
  `sf` / `sfc`. Several features are unioned into one.

- path:

  directory holding the ERA5-Land files (netCDF or GRIB); see
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  for how files are matched and the reader backend chosen.

- method:

  spatial sampling, default `"area"`. See
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  for `"area"`, `"area_mean"`, `"bilinear"` and `"nearest"`.

- id, name:

  optional labels stored on the result as attributes `lake_id` /
  `lake_name` - handy when binding many lakes together.

- ...:

  further arguments for
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  (`years`, `months`, `variables`, `tz`, `format`, `precip_units`,
  `pressure_units`, `pattern`, `max_dist_km`, `outfile`, `fill_gaps`,
  `verbose`).

## Value

the data frame from
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md),
with extra attributes `lake_id` and `lake_name`.

## Details

For a point, a raw geometry, or full control use
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
directly.

## Examples

``` r
if (FALSE) { # \dontrun{
poly <- sf::st_read("gis/rotorua.gpkg")

met <- extract_era5_lake_met(
  poly,
  path    = "era5_land",
  years   = 2023:2024,
  name    = "Rotorua",
  outfile = "rotorua_era5_hourly_met.csv")

## batch over a multi-lake layer
lakes <- sf::st_read("gis/lakes.gpkg")
mets  <- lapply(seq_len(nrow(lakes)), function(i)
  extract_era5_lake_met(lakes[i, ], path = "era5_land", years = 2024,
                        id = lakes$id[i], name = lakes$name[i]))
} # }
```
