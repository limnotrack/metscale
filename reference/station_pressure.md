# Station pressure from elevation

Hypsometric equation using virtual temperature, i.e. accounting for the
moisture content of the air.

## Usage

``` r
station_pressure(airt, relh, elev, mslp = 101325)
```

## Arguments

- airt:

  air temperature, degC.

- relh:

  relative humidity, percent.

- elev:

  elevation, m above sea level.

- mslp:

  mean sea level pressure, Pa (default standard atmosphere).

## Value

station pressure, **Pa**.

## Examples

``` r
station_pressure(15, 70, elev = 280)
#> [1] 98031.09
```
