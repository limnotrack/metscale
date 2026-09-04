# Expand a minimal meteorological set to a complete one

Derives every variable a lake model may ask for from a small required
core, filling in only what is missing: relative humidity and dew point
from each other, vapour pressure, cloud cover from measured shortwave
([`calc_cc()`](http://limnotrack.com/climprep/reference/calc_cc.md)),
downwelling longwave
([`calc_in_lwr()`](http://limnotrack.com/climprep/reference/calc_in_lwr.md)),
station and sea level pressure, wind speed/direction and u/v components,
and snowfall.

## Usage

``` r
expand_met(met, lat, lon, elev = 0, tz = "Etc/GMT-12", round_to = 3)
```

## Arguments

- met:

  data frame with a `Date` column (`Date` or POSIXct) and the `MET_*`
  columns above. Any timestep; nothing is resampled.

- lat, lon:

  lake position, decimal degrees.

- elev:

  lake surface elevation, m above sea level.

- tz:

  timezone the timestamps refer to, used for the solar geometry in
  [`calc_cc()`](http://limnotrack.com/climprep/reference/calc_cc.md).
  Default `"Etc/GMT-12"` (fixed NZST). Ignored when `MET_cldcvr` is
  supplied.

- round_to:

  decimal places for the returned values, or `NULL` to leave unrounded.

## Value

data frame with `Date` and `MET_radswd`, `MET_radlwd`, `MET_cldcvr`,
`MET_tmpair`, `MET_humrel`, `MET_tmpdew`, `MET_prvapr`, `MET_prsttn`,
`MET_prmslp`, `MET_wndspd`, `MET_wnddir`, `MET_wnduvu`, `MET_wnduvv`,
`MET_pprain`, `MET_ppsnow`.

## Details

Required: `MET_radswd` (W m-2), `MET_tmpair` (degC), `MET_pprain` (mm
per timestep), one of `MET_humrel` (percent) / `MET_tmpdew` (degC), and
wind as either `MET_wndspd` (m/s) or both `MET_wnduvu` and `MET_wnduvv`.

## Examples

``` r
met <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 5),
                  MET_radswd = c(300, 120, 280, 90, 310),
                  MET_tmpair = c(18, 16, 19, 15, 20),
                  MET_humrel = c(70, 85, 65, 90, 60),
                  MET_wndspd = c(3, 5, 2, 6, 3),
                  MET_pprain = c(0, 12, 0, 25, 0))
expand_met(met, lat = -38.08, lon = 176.27, elev = 280)
#>         Date MET_radswd MET_radlwd MET_cldcvr MET_tmpair MET_humrel MET_tmpdew
#> 1 2024-01-01        300    285.810      0.623         18         70     12.447
#> 2 2024-01-02        120    386.860      1.000         16         85     13.479
#> 3 2024-01-03        280    303.589      0.681         19         65     12.272
#> 4 2024-01-04         90    381.536      1.000         15         90     13.373
#> 5 2024-01-05        310    285.604      0.589         20         60     12.000
#>   MET_prvapr MET_prsttn MET_prmslp MET_wndspd MET_wnddir MET_wnduvu MET_wnduvv
#> 1     14.452   98067.55   101333.4          3        180          0          3
#> 2     15.459   98046.62   101334.7          5        180          0          5
#> 3     14.287   98078.32   101333.2          2        180          0          2
#> 4     15.352   98035.30   101334.5          6        180          0          6
#> 5     14.034   98088.91   101332.9          3        180          0          3
#>   MET_pprain MET_ppsnow
#> 1          0          0
#> 2         12          0
#> 3          0          0
#> 4         25          0
#> 5          0          0
```
