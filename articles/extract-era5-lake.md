# Extracting ERA5-Land over a lake

Once you have hourly ERA5-Land netCDF or GRIB on disk (see
[`vignette("download-era5")`](http://limnotrack.com/metscale/articles/download-era5.md)),
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
pulls a `metscale`-shaped hourly series out of it for a point or a
polygon.
[`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
is a thin wrapper that takes a lake polygon and defaults to the
area-weighted method. The code chunks here are **not executed** (they
need the reanalysis archive); the one exception is reading the bundled
lake polygon.

``` r

library(metscale)
ex <- system.file("extdata", package = "metscale")
```

## Point extraction

``` r

met <- extract_era5_hourly_met(
  path      = "era5_netcdf",          # directory of monthly hourly .nc files
  lon       = 176.2717,
  lat       = -38.0790,
  years     = 2023:2025,
  method    = "bilinear",             # 4 nodes around the point
  tz        = "Etc/GMT-12",
  format    = "AEME")                 # MET_* names and units
```

Files are located by matching `pattern` against the names in `path`. The
default, `"{variable}"`, finds any `.nc` / `.grib` file whose name holds
the ERA5 variable name and a 4-digit year – enough for
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)
output and most ad-hoc layouts. Give it explicitly to disambiguate or to
filter by month, e.g. `pattern = "{year}_{month}_{variable}"` or
`pattern = "*_{variable}_hourly_{year}_{month}_*"`; `{year}` / `{month}`
are optional and `*` is a wildcard. `variables` defaults to the nine
ERA5-Land fields `metscale` needs; `precip_units` and `pressure_units`
control the output units (`"mm/hr"` and `"Pa"` by default).
`fill_gaps = TRUE` reindexes onto a complete regular hourly sequence.

## Polygon (lake-average) extraction

A lake wider than an ERA5-Land grid cell (~0.1°, roughly 9 km at this
latitude) covers several cells, and a point sample then depends on
exactly where the point falls. Averaging over the cells that overlap the
lake polygon is more stable. Pass the geometry as `geom`:

``` r

lake_poly <- readRDS(file.path(ex, "rotorua_lake_shape.rds"))   # an sf polygon

met_area <- extract_era5_hourly_met(
  path   = "era5_netcdf",
  geom   = lake_poly,
  years  = 2023:2025,
  method = "area",                    # area-weighted mean of overlapping cells
  tz     = "Etc/GMT-12")
```

`method` chooses the spatial sampling:

| `method` | what it does | use when |
|----|----|----|
| `"nearest"` | single closest cell centre | lake well inside one cell |
| `"bilinear"` | 4 cell centres around the centroid | point-like water body (default) |
| `"area_mean"` | unweighted mean of cells overlapping the polygon | lake spans a few cells |
| `"area"` | **area-weighted** mean of overlapping cells | lake spans several cells unevenly |

The bundled Lake Rotorua polygon spans more than one cell, so `"area"`
is the right choice:

``` r

lake_poly <- readRDS(file.path(ex, "rotorua_lake_shape.rds"))
sf::st_crs(lake_poly)$epsg          # 2193 (NZTM); any CRS is accepted
#> [1] 2193
round(as.numeric(sum(sf::st_area(lake_poly))) / 1e6, 1)   # lake area, km^2
#> [1] 82
sf::st_bbox(sf::st_transform(lake_poly, 4326))            # ~0.11 deg E-W
#>      xmin      ymin      xmax      ymax 
#> 176.21613 -38.14151 176.32674 -38.03251
```

An ~0.11° east–west extent against a ~0.1° grid means the lake touches
two to three cells in each direction — exactly the case area-weighting
is for.

## `extract_era5_lake_met()` — the polygon wrapper

[`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
is the same call with two conveniences: `method` defaults to `"area"`,
and optional `id` / `name` are stored on the result as `lake_id` /
`lake_name` attributes. The polygon can be an `sf` / `sfc` object or a
path to a vector file (`.gpkg`, `.shp`, `.rds`).

``` r

met <- extract_era5_lake_met(
  lake_poly,                     # or "gis/rotorua.gpkg"
  path    = "era5_netcdf",
  years   = 2023:2025,
  name    = "Rotorua",
  outfile = "rotorua_era5_hourly_met.csv")

## batch over a multi-lake layer
lakes <- sf::st_read("gis/lakes.gpkg")
mets  <- lapply(seq_len(nrow(lakes)), function(i)
  extract_era5_lake_met(lakes[i, ], path = "era5_netcdf", years = 2024,
                        id = lakes$id[i], name = lakes$name[i]))
```

The bundled `rotorua_era5_hourly_met.csv.gz` used throughout the other
vignettes is the output of exactly this call for Lake Rotorua.

## See also

- [`vignette("download-era5")`](http://limnotrack.com/metscale/articles/download-era5.md)
  — getting the netCDF in the first place.
- [`vignette("met-data-frames")`](http://limnotrack.com/metscale/articles/met-data-frames.md)
  — the `MET_*` names, units and time-zone convention the extractor
  output follows.
- [`vignette("bias-correction-methods")`](http://limnotrack.com/metscale/articles/bias-correction-methods.md)
  — correcting the extracted series against local observations.
