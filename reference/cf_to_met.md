# Convert CF / CMIP meteorology back to the AEME `MET_*` scheme

The inverse of
[`met_to_cf()`](http://limnotrack.com/climprep/reference/met_to_cf.md):
renames `tas`, `pr`, `sfcWind`, ... to the AEME `MET_*` names and
converts units back (K -\> degC, Pa -\> hPa for vapour pressure, percent
-\> fraction for cloud cover, `kg m-2 s-1` -\> "mm per timestep" for
precipitation and snowfall). Unmapped columns pass through.

## Usage

``` r
cf_to_met(cf, vars = NULL, timestep = NULL, time_name = "Date", outfile = NULL)
```

## Arguments

- cf:

  data frame with a time column plus CF/CMIP short-name columns, or a
  path to a `.csv` / `.rds` file.

- vars:

  optional subset of CF names to convert; default every mapped column
  present.

- timestep:

  seconds per row for the precipitation flux -\> depth conversion;
  inferred from the time column when `NULL`.

- time_name:

  name for the time column in the output (default `"Date"`).

- outfile:

  optional output path
  ([`utils::write.csv`](https://rdrr.io/r/utils/write.table.html)).

## Value

the data frame with `MET_*` columns in AEME units.

## See also

[`met_to_cf()`](http://limnotrack.com/climprep/reference/met_to_cf.md)

## Examples

``` r
cf <- data.frame(time = seq(as.POSIXct("2024-01-01", tz = "UTC"),
                            by = "hour", length.out = 3),
                 tas = c(288.15, 288.55, 289.15), pr = c(0, 5.5e-5, 3e-4))
cf_to_met(cf)
#>                  Date MET_tmpair MET_pprain
#> 1 2024-01-01 00:00:00       15.0      0.000
#> 2 2024-01-01 01:00:00       15.4      0.198
#> 3 2024-01-01 02:00:00       16.0      1.080
```
