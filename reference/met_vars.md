# Standard meteorological variables, names and units

Standard meteorological variables, names and units

## Usage

``` r
met_vars()
```

## Value

data frame with `variable`, `name` and `unit` columns.

## Examples

``` r
met_vars()
#>                 variable       name            unit
#> 1    Shortwave radiation MET_radswd            W/m2
#> 2     Longwave radiation MET_radlwd            W/m2
#> 3            Cloud cover MET_cldcvr  fraction (0-1)
#> 4        Air temperature MET_tmpair            degC
#> 5      Relative humidity MET_humrel               %
#> 6  Dew point temperature MET_tmpdew            degC
#> 7        Vapour pressure MET_prvapr             hPa
#> 8       Station pressure MET_prsttn              Pa
#> 9     Sea level pressure MET_prmslp              Pa
#> 10            Wind speed MET_wndspd             m/s
#> 11        Wind direction MET_wnddir  degrees (from)
#> 12         Eastward wind MET_wnduvu             m/s
#> 13        Northward wind MET_wnduvv             m/s
#> 14              Rainfall MET_pprain mm per timestep
#> 15              Snowfall MET_ppsnow mm per timestep
```
