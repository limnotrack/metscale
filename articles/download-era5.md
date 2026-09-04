# Download ERA5 data

``` r

library(climprep)
```

`climprep`’s bias-correction and disaggregation tools operate on a
meteorology data frame. This vignette covers the three ways to *acquire*
ERA5 forcing, from lightest to heaviest. Whichever you use, the output
feeds into
[`standardise_met()`](http://limnotrack.com/climprep/reference/standardise_met.md),
[`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md)
and
[`disaggregate_met_to_hourly()`](http://limnotrack.com/climprep/reference/disaggregate_met_to_hourly.md).

All three functions need suggested packages that are **not** installed
with `climprep` by default:

``` r

install.packages(c("httr2", "jsonlite", "terra", "ecmwfr", "stars", "sf"))
```

## 1. Point time series from ISIMIP3a — `download_era5_isimip_point()`

The quickest route.
[`download_era5_isimip_point()`](http://limnotrack.com/climprep/reference/download_era5_isimip_point.md)
pulls daily ERA5 (20CRv3-ERA5, ISIMIP3a `obsclim`) from the [ISIMIP
repository API](https://files.isimip.org/api/v2) for any point on the
globe. No account or key is required. Coverage currently runs to 2021.

``` r

lon <- 98.67591   # Lake Toba, Indonesia
lat <- 2.637047
years <- 2015:2021
vars <- c("MET_tmpair", "MET_pprain")

met <- download_era5_isimip_point(lon, lat, years, vars)
summary(met)
```

Variable names may be given either as AEME `MET_*` names or as the
ERA5/CMIP short names (`tas`, `pr`, `sfcwind`, `rsds`, `ps`, `rlds`,
`hurs`). The result has a `Date` column plus one column per variable,
already in AEME names and units (degC, mm/day, …).

## 2. Gridded GRIB from the Copernicus Data Store — `download_era5_cds()`

For the full hourly ERA5 / ERA5-Land archive you need a free [Copernicus
Data Store (CDS)](https://cds.climate.copernicus.eu/user/register)
account, linked to your session with
[`ecmwfr::wf_set_key()`](https://rdrr.io/pkg/ecmwfr/man/wf_set_key.html).
See the [ecmwfr
documentation](https://bluegreen-labs.github.io/ecmwfr/#use).

``` r

ecmwfr::wf_set_key(key = Sys.getenv("CDS_KEY"), user = Sys.getenv("CDS_USER"))
```

[`download_era5_cds()`](http://limnotrack.com/climprep/reference/download_era5_cds.md)
submits one CDS request per variable / year / month (batched, up to 20
at a time) and writes a GRIB file per request. Give it a point plus
`buffer`, or an `sf` polygon as `shape`.

``` r

year <- 2024
month <- 1
files <- download_era5_cds(
  lat = lat, lon = lon, year = year, month = month,
  variable = "2m_temperature", path = "data/test", site = "toba",
  user = Sys.getenv("CDS_USER")
)
files
```

Extract a point (or polygon-mean) time series from the downloaded GRIB
with
[`read_era5_grib_point()`](http://limnotrack.com/climprep/reference/read_era5_grib_point.md):

``` r

df <- read_era5_grib_point(file = files, lat = lat, lon = lon)
head(df)
```

## 3. Aggregate downloaded netCDF to daily — `convert_era5_netcdf()`

If you already have hourly ERA5 netCDF on disk (named
`era5_<variable>_hourly_<year>_<site>.nc`),
[`convert_era5_netcdf()`](http://limnotrack.com/climprep/reference/convert_era5_netcdf.md)
aggregates each variable to daily with the appropriate function (mean,
or max for precipitation / radiation) and returns AEME or LakeEnsemblR
columns.

``` r

met <- convert_era5_netcdf(
  lat = lat, lon = lon, year = 2022:2023,
  path = "era5_netcdf", site = "toba", format = "AEME"
)
```

For **hourly** extraction from ERA5-Land netCDF — with de-accumulation
of the flux variables, unit conversion and a time-zone shift — use
[`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
/
[`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md)
instead.

`convert_era5_netcdf(format = "raw")` returns the ERA5 nc short names
(`t2m`, `d2m`, `ssrd`, `strd`, …), which
[`standardise_met()`](http://limnotrack.com/climprep/reference/standardise_met.md)
recognises directly:

``` r

met_raw <- convert_era5_netcdf(lat = lat, lon = lon, year = 2022,
                               path = "era5_netcdf", format = "raw")
std <- standardise_met(met_raw)
```

## Next steps

- [`standardise_met()`](http://limnotrack.com/climprep/reference/standardise_met.md)
  — column names, units, time zone, resampling.
- [`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md)
  /
  [`apply_met_bias_correction()`](http://limnotrack.com/climprep/reference/apply_met_bias_correction.md)
  — correct ERA5 against local observations.
- [`disaggregate_met_to_hourly()`](http://limnotrack.com/climprep/reference/disaggregate_met_to_hourly.md)
  — daily back to sub-daily.
- [`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
  — derive the remaining variables a lake model needs.
