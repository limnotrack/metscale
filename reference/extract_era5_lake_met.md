# Hourly ERA5-Land meteorology for one named lake

Convenience wrapper around
[`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
that looks a lake up in a polygon layer by id or name and forwards its
geometry.

## Usage

``` r
extract_era5_lake_met(
  lake,
  path,
  lakes = NULL,
  layer = "updated",
  method = c("area", "area_mean", "bilinear", "nearest"),
  ...
)
```

## Arguments

- lake:

  a lake identifier matched against `id_final` (e.g. `"LID 1"` or
  `"1"`), `id_LID`, `name_final`, `name_fenz`, `name_english` or
  `name_maori` (case-insensitive); or an `sf`/`sfc` polygon to use
  directly, in which case `lakes` is not needed.

- path:

  directory with the ERA5-Land netCDF files.

- lakes:

  an `sf` polygon layer, a named list of such layers (see `layer`), or a
  path to an `.rds` holding either. Required unless `lake` is itself a
  geometry.

- layer:

  when `lakes` is a list of layers, which element to use. Default
  `"updated"`, falling back to the only/first element.

- method:

  spatial sampling passed to
  [`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md):
  `"area"` (area-weighted mean of every overlapping ERA5 cell - best
  when a lake straddles several cells), `"area_mean"` (unweighted mean
  of overlapping cells), `"bilinear"` (4 nodes around the lake centroid,
  the default) or `"nearest"`.

- ...:

  further arguments for
  [`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
  (`years`, `months`, `variables`, `tz`, `format`, `precip_units`,
  `pressure_units`, `outfile`, `fill_gaps`, `verbose`).

## Value

the data frame from
[`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md),
with extra attributes `lake_id` and `lake_name`.

## Details

The lookup is aimed at the LERNZmp `lernzmp_lakes_master` layer (a list
with `original` / `updated` `sf` layers in NZGD2000 / NZTM, EPSG:2193)
but works with any `sf` layer carrying one or more of the identifier
columns listed under `lake`.

## Examples

``` r
if (FALSE) { # \dontrun{
lakes <- readRDS("gis/lake_shapefile/lernzmp_lakes_master.rds")

met <- extract_era5_lake_met(
  lake   = "Rotorua",
  path   = "download_era5-land/era5_netcdf",
  lakes  = lakes,
  method = "area",
  years  = 2023:2024,
  outfile = "rotorua_era5_hourly_met.csv")

## loop over a set of lakes
ids <- c("LID 25994", "LID 25998", "LID 54732")
mets <- lapply(ids, extract_era5_lake_met,
               path = "download_era5-land/era5_netcdf",
               lakes = lakes, method = "area", years = 2024)
} # }
```
