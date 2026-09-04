# Relative humidity from air temperature and dew point

Relative humidity from air temperature and dew point

## Usage

``` r
dewpoint_to_rh(airt, dewt)
```

## Arguments

- airt:

  air temperature, degC.

- dewt:

  dew point temperature, degC.

## Value

relative humidity, percent, capped at 100.

## Examples

``` r
dewpoint_to_rh(20, 13.2)
#> [1] 64.91039
```
