# Read a point from an ERA5 GRIB file

Extract a time series at a point (or the weighted mean over a polygon)
from one or more GRIB files downloaded with
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md).

## Usage

``` r
read_era5_grib_point(file, shape = NULL, lat, lon, method = "bilinear")
```

## Arguments

- file:

  character; path to the GRIB file. Can be a vector of paths.

- shape:

  sf object; polygon over which to take a weighted mean. If `NULL`
  (default) the value is extracted at `lon`/`lat`.

- lat:

  numeric; latitude.

- lon:

  numeric; longitude.

- method:

  character; interpolation method passed to
  [`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html)
  for point extraction. Default "bilinear".

## Value

A data frame with columns `DateTime`, `value`, `units`, `variable` and
`short_name`, sorted by `DateTime`.

## Details

Requires the suggested package terra (and sf when `shape` is supplied).

## See also

[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)

## Examples

``` r
if (FALSE) { # \dontrun{
lat <- -38.07782
lon <- 176.2673
files <- download_era5_cds(lat = lat, lon = lon, year = 2024, month = 1:2,
                           variable = "2m_temperature", path = "data/test",
                           user = "person@email.com")
df <- read_era5_grib_point(file = files, lat = lat, lon = lon)
} # }
```
