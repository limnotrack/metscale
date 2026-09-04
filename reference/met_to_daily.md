# Aggregate a (sub-)hourly met frame to daily

Rain/snow are summed, everything else averaged; `Date` is returned as
class `Date`, which is what lake-model builders such as
[`AEME::build_aeme()`](https://limnotrack.com/reference/build_aeme.html)
expect.

## Usage

``` r
met_to_daily(met, tz = NULL, min_frac = 0.5)
```

## Arguments

- met:

  data frame with `Date` (POSIXct) + `MET_*` columns.

- tz:

  time zone used to assign calendar days (default: the `tz` attribute of
  `met`, else `"Etc/GMT-12"`).

- min_frac:

  drop days with less than this fraction of expected hourly records
  (default 0.5); set 0 to keep all.

## Value

daily data frame, `Date` first.

## Examples

``` r
h <- data.frame(Date = seq(as.POSIXct("2024-01-01", tz = "Etc/GMT-12"),
                           by = "hour", length.out = 48),
                MET_tmpair = rnorm(48, 15), MET_pprain = 0.1)
met_to_daily(h)
#>         Date MET_tmpair MET_pprain
#> 1 2024-01-01   14.91357        2.4
#> 2 2024-01-02   15.14154        2.4
```
