# Humidity variables using the GOTM bulk formulation

Vectorised port of
[`AEME::calc_humidity_vars()`](https://limnotrack.com/reference/calc_humidity_vars.html):
saturation and actual vapour pressure, specific humidities and moist air
density, from any of four humidity inputs.

## Usage

``` r
calc_humidity_vars(
  hum,
  hum_method = 1,
  airp,
  tw,
  ta,
  rgas = 287.05,
  kelvin = 273.15,
  const06 = 0.62198
)
```

## Arguments

- hum:

  humidity input, interpreted according to `hum_method`.

- hum_method:

  `1` relative humidity (percent), `2` wet-bulb temperature, `3` dew
  point temperature, `4` specific humidity (kg/kg).

- airp:

  air pressure, Pa.

- tw:

  water-surface temperature, degC (or K, auto-detected).

- ta:

  air temperature, degC (or K, auto-detected).

- rgas:

  gas constant for dry air, J/kg/K.

- kelvin:

  degC to K offset.

- const06:

  ratio of molecular weights of water and dry air.

## Value

list of numeric vectors: `es`, `qs`, `ea`, `qa`, `rhoa`.

## Examples

``` r
calc_humidity_vars(hum = 70, hum_method = 1, airp = 101325,
                   tw = 18, ta = 15)
#> $es
#> [1] 2021.535
#> 
#> $qs
#> [1] 0.01250316
#> 
#> $ea
#> [1] 1192.933
#> 
#> $qa
#> [1] 0.007355426
#> 
#> $rhoa
#> [1] 1.219433
#> 
```
