# Clear-sky downwelling shortwave radiation

GOTM `shortwave_radiation.F90`: Bird-type direct + diffuse beam under a
bulk atmospheric transmission, modulated by cloud fraction.

## Usage

``` r
clear_sky_swr(datetime, lat, lon, cloud = 0)
```

## Arguments

- datetime:

  POSIXct (or Date, treated as 00:00 UTC).

- lat, lon:

  position in decimal degrees.

- cloud:

  cloud fraction, 0-1; scalar or vector (default 0 = clear sky).

## Value

numeric vector, W m-2; zero at night.

## Examples

``` r
t <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 24)
clear_sky_swr(t, lat = -38.08, lon = 176.27)
#>  [1] 1041.518475 1025.937640  949.849325  819.153765  644.426155  441.312828
#>  [7]  233.171490   62.740831    0.000000    0.000000    0.000000    0.000000
#> [13]    0.000000    0.000000    0.000000    0.000000    0.000000    4.963394
#> [19]  139.660866  336.466424  545.746955  736.914248  891.126169  995.401049
```
