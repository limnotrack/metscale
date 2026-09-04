# Dew point temperature from air temperature and relative humidity

Magnus-Tetens with the Alduchov & Eskridge coefficients (Lawrence 2005);
uncertainty about 0.35 degC.

## Usage

``` r
rh_to_dewpoint(airt, relh)
```

## Arguments

- airt:

  air temperature, degC.

- relh:

  relative humidity, percent (0-100).

## Value

dew point temperature, degC.

## Examples

``` r
rh_to_dewpoint(20, 65)
#> [1] 13.22115
```
