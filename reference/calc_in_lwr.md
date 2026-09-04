# Downwelling longwave radiation

Clear-sky emissivity after Idso & Jackson with a cloud correction; the
formulation used by `AEME::calc_in_lwr()` (originally `gotmtools`).

## Usage

``` r
calc_in_lwr(cc, airt, relh = NULL, dewt = NULL)
```

## Arguments

- cc:

  cloud cover fraction, 0-1.

- airt:

  air temperature, degC.

- relh:

  relative humidity, percent. Used to derive `dewt` when that is not
  supplied.

- dewt:

  dew point temperature, degC. Takes precedence over `relh`.

## Value

downwelling longwave irradiance, W m-2.

## Examples

``` r
calc_in_lwr(cc = 0.4, airt = 15, relh = 70)
#> [1] 232.0721
```
