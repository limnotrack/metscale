# Actual vapour pressure

Eqn. C2 of TVA (1972) as used in the DYRESM manual - the formulation
[`AEME::expand_met()`](https://limnotrack.com/reference/expand_met.html)
uses for `MET_prvapr`.

## Usage

``` r
vapour_pressure(airt, relh)
```

## Arguments

- airt:

  air temperature, degC.

- relh:

  relative humidity, percent.

## Value

vapour pressure, hPa.

## Examples

``` r
vapour_pressure(20, 65)
#> [1] 15.20327
```
