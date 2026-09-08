# Preview the extraction grid, cells and geometry before extracting

A sanity-check map drawn straight from the files that
[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
/
[`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
would read: the ERA5-Land grid around your location, the cell(s) that
the chosen `method` would actually sample (shaded by weight), the
land/sea validity mask, and your point or polygon on top. Use it to
confirm the geometry lands where you expect and overlaps sensible cells
*before* running an extraction.

## Usage

``` r
plot_extract_grid(
  path,
  lon = NULL,
  lat = NULL,
  geom = NULL,
  method = c("bilinear", "nearest", "area", "area_mean"),
  variables = "2m_temperature",
  pattern = "{variable}",
  years = NULL,
  months = 1:12,
  area_crs = 2193,
  max_dist_km = 50,
  pad = 3,
  engine = c("ggplot2", "base")
)
```

## Arguments

- path:

  directory holding the ERA5-Land files (netCDF or GRIB), as passed to
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md).

- lon, lat:

  point of interest, decimal degrees (WGS84). Ignored if `geom` is
  supplied.

- geom:

  an `sf`/`sfc` point or polygon (any CRS); overrides `lon`/`lat`. A
  polygon is required for `method = "area"` / `"area_mean"`.

- method:

  spatial sampling to preview: `"bilinear"` (default), `"nearest"`,
  `"area"` or `"area_mean"`. See
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md).

- variables:

  ERA5-Land variable name(s); the first one with files on disk is used
  to read the grid. Default `"2m_temperature"`.

- pattern:

  file-name template, as in
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md).
  Default `"{variable}"`.

- years, months:

  optional filters passed to the file matcher (only needed when
  `pattern` pins `{year}` / `{month}`).

- area_crs:

  projected CRS for the `"area"` intersection, matching the extractor.
  Default `2193` (NZTM 2000).

- max_dist_km:

  distance cap for a `"nearest"` sample. Unlike the extractor this only
  warns (the plot is still drawn) so you can see how far off a
  mis-placed point is. Default `50`.

- pad:

  number of grid cells of context to draw around the geometry. Default
  `3`.

- engine:

  `"ggplot2"` (default, returns a `ggplot` you can further style or hand
  to `mapview`/`tmap`) or `"base"` (draws with
  [`sf::plot()`](https://r-spatial.github.io/sf/reference/plot.html),
  returns the grid invisibly). `"ggplot2"` falls back to `"base"` if
  ggplot2 is not installed.

## Value

For `engine = "ggplot2"`, a `ggplot` object; for `"base"`, the grid `sf`
(invisibly). Either way the return carries attributes `grid` (an `sf` of
the drawn cells with columns `ix`, `iy`, `weight`, `selected`, `land`),
`weights` (the `data.frame(ix, iy, w)` selection) and `file` (the file
read).

## Details

The grid, cell selection and weights come from the same internal
machinery as the extractors, so what you see is what you would get. Only
one file is opened (the first that matches `pattern` for the first
available `variables` entry) - grids are identical across ERA5-Land
variables and months.

On the map:

- filled cells are the ones `method` samples, coloured by their weight
  (`"nearest"` -\> one cell, weight 1; `"bilinear"` -\> up to four;
  `"area"` / `"area_mean"` -\> every cell the polygon overlaps);

- grey cells are in view but not sampled;

- a dashed blue outline marks cells masked out by ERA5-Land (sea, or the
  lake pixels themselves) - these are dropped and their weight
  redistributed;

- grey dots are grid nodes (cell centres);

- the red polygon / red cross is your `geom` (or `lon`/`lat`).

## See also

[`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md),
[`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)

## Examples

``` r
if (FALSE) { # \dontrun{
## point, bilinear
plot_extract_grid("era5_land", lon = 176.2717, lat = -38.0790)

## lake polygon, area-weighted - the case worth eyeballing
poly <- sf::st_read("gis/rotorua.gpkg")
p <- plot_extract_grid("era5_land", geom = poly, method = "area")
p + ggplot2::coord_sf(expand = FALSE)

## interactive check against a basemap, no new dependency in the package
mapview::mapview(attr(p, "grid"), zcol = "weight")
} # }
```
