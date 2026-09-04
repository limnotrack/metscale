# Solar zenith angle

GOTM `solar_zenith_angle.F90`. Evaluated at the true UTC instant of
`datetime`, so the result is independent of the `tzone` attribute.

## Usage

``` r
solar_zenith_angle(datetime, lat, lon)
```

## Arguments

- datetime:

  POSIXct (or Date, treated as 00:00 UTC).

- lat, lon:

  position in decimal degrees.

## Value

numeric vector of zenith angles in degrees; 90 when the sun is at or
below the horizon.

## Examples

``` r
t <- seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 24)
solar_zenith_angle(t, lat = -38.08, lon = 176.27)
#>  [1] 15.43462 17.91836 27.04835 38.23631 49.97009 61.73913 73.26605 84.30941
#>  [9] 90.00000 90.00000 90.00000 90.00000 90.00000 90.00000 90.00000 90.00000
#> [17] 90.00000 89.53702 78.83475 67.51689 55.83826 44.04511 32.49069 22.01402
```
