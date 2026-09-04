# Mean diurnal cycle of an hourly meteorological record

Summarises an hourly record into, for each variable and calendar month,
the average shape of the day: an anomaly about the daily mean for
additive variables (temperature, humidity, pressure, longwave) and a
normalised factor for multiplicative ones (wind speed, shortwave,
precipitation). Used by
[`disaggregate_met_to_hourly()`](http://limnotrack.com/climprep/reference/disaggregate_met_to_hourly.md)
with `method = "diurnal"`.

## Usage

``` r
build_diurnal_climatology(hourly, tz = NULL, vars = NULL, n_sub = 24)
```

## Arguments

- hourly:

  data frame with `Date` (POSIXct) and `MET_*` columns, e.g. from
  [`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md).

- tz:

  timezone in which the diurnal cycle is expressed. Defaults to the `tz`
  attribute of `hourly`, else `"Etc/GMT-12"`.

- vars:

  variables to summarise; default all `MET_*` columns present.

- n_sub:

  steps per day (24 hourly, 8 three-hourly).

## Value

object of class `diurnal_climatology`: a list with `shape` (a named list
of `12 x n_sub` matrices), `kind` (`"additive"` or `"ratio"` per
variable), `n_days` per month, `tz` and `n_sub`.

## Examples

``` r
set.seed(1)
h <- data.frame(
  Date = seq(as.POSIXct("2024-01-01", tz = "Etc/GMT-12"),
             by = "hour", length.out = 24 * 60),
  MET_tmpair = 15 + 5 * sin(seq_len(24 * 60) * 2 * pi / 24) + rnorm(24 * 60))
dc <- build_diurnal_climatology(h)
round(dc$shape$MET_tmpair[1, ], 2)
#>  [1]  1.22  2.54  3.45  4.16  4.76  4.83  4.86  4.33  3.45  2.86  1.25  0.07
#> [13] -1.21 -2.42 -3.32 -4.41 -4.77 -5.04 -4.81 -4.31 -3.89 -2.57 -1.23  0.20
```
