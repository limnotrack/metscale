# Convert between station and mean sea level pressure

Convert between station and mean sea level pressure

## Usage

``` r
mslp_from_station(prsttn, elev, airt)

station_from_mslp(prmslp, elev, airt)
```

## Arguments

- prsttn:

  station pressure, Pa.

- elev:

  elevation, m.

- airt:

  air temperature, degC.

- prmslp:

  mean sea level pressure, Pa.

## Value

the converted pressure, Pa.

## Examples

``` r
mslp_from_station(97300, elev = 280, airt = 15)
#> [1] 100574.5
```
