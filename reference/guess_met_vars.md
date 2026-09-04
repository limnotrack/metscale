# Guess standard `MET_*` names from arbitrary column names

Case-insensitive pattern matching against a built-in synonym table
covering common logger, council, NIWA/CliFlo, ERA5 and CMIP naming.

## Usage

``` r
guess_met_vars(x)
```

## Arguments

- x:

  character vector of column names.

## Value

character vector the same length as `x`, holding the matched `MET_*`
name or `NA` where nothing matched.

## Examples

``` r
guess_met_vars(c("AirTemp_C", "WindSpd", "SolarRad", "junk"))
#> [1] "MET_tmpair" "MET_wndspd" "MET_radswd" NA          
```
