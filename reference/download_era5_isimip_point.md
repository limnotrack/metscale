# Download ERA5 data from ISIMIP3a for a point location

Download daily ERA5 (20CRv3-ERA5, ISIMIP3a `obsclim`) meteorology for a
point location, anywhere globally, for the period covered by ISIMIP3a
(currently up to 2021). Data are pulled from the [ISIMIP repository
API](https://files.isimip.org/api/v2); no account or key is required.

## Usage

``` r
download_era5_isimip_point(
  lon,
  lat,
  years,
  vars = c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd", "MET_prsttn",
    "MET_radlwd", "MET_humrel"),
  download_path = tempdir()
)
```

## Arguments

- lon:

  numeric; longitude.

- lat:

  numeric; latitude.

- years:

  numeric; vector of years to extract.

- vars:

  character; AEME meteorological variable names to download. Defaults to
  all available:
  `c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd", "MET_prsttn", "MET_radlwd", "MET_humrel")`.
  ERA5/CMIP short names (`tas`, `pr`, `sfcwind`, `rsds`, `ps`, `rlds`,
  `hurs`) are also accepted.

- download_path:

  character; path to download the data. Default is the temporary
  directory.

## Value

A data frame with a `Date` column and one column per requested variable.

## Details

Requires the suggested packages httr2, jsonlite and terra.

## Examples

``` r
if (FALSE) { # \dontrun{
lon <- 13.064332
lat <- 52.380551
years <- 2015:2021
vars <- c("MET_tmpair", "MET_pprain")
download_era5_isimip_point(lon, lat, years, vars)
} # }
```
