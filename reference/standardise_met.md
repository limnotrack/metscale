# Standardise meteorological names and units

Renames columns to the standard `MET_*` names with
[`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md),
then detects and corrects common unit mistakes from the value ranges:
Kelvin to degC, hPa to Pa, humidity fraction to percent, oktas to
fraction, km/h to m/s, metres to millimetres, and MJ or kJ m-2 day-1 to
W m-2.

## Usage

``` r
standardise_met(met, verbose = TRUE)
```

## Arguments

- met:

  data frame with a date/time column and meteorological columns.

- verbose:

  report each rename and conversion.

## Value

`met` with standard names and units, the time column renamed to `Date`.
Unmatched columns are kept unchanged with a warning.

## Examples

``` r
raw <- data.frame(timestamp = as.Date("2024-01-01") + 0:4,
                  AirTemp_K = c(291, 289, 292, 288, 293),
                  WindSpd_kmh = c(11, 18, 7, 22, 11),
                  SolarRad = c(300, 120, 280, 90, 310),
                  Rain_mm = c(0, 12, 0, 25, 0))
standardise_met(raw)
#> date column: timestamp -> Date
#> renamed: AirTemp_K -> MET_tmpair, WindSpd_kmh -> MET_wndspd, SolarRad -> MET_radswd, Rain_mm -> MET_pprain
#> MET_tmpair: K -> degC
#>         Date MET_tmpair MET_wndspd MET_radswd MET_pprain
#> 1 2024-01-01      17.85         11        300          0
#> 2 2024-01-02      15.85         18        120         12
#> 3 2024-01-03      18.85          7        280          0
#> 4 2024-01-04      14.85         22         90         25
#> 5 2024-01-05      19.85         11        310          0
```
