# Estimate sub-daily shortwave radiation from daily means

Builds a clear-sky irradiance curve from solar geometry and rescales it
so that each day's mean reproduces the supplied daily mean `MET_radswd`.
This preserves the observed daily energy while giving a physically
shaped diurnal cycle with genuine night-time zeros.

## Usage

``` r
estimate_hourly_swr(
  met,
  lat,
  lon,
  tz = "Etc/GMT-12",
  timestep = c("hour", "3hour"),
  interval = c("ending", "beginning", "instant"),
  cloud = 0
)
```

## Arguments

- met:

  data frame with a `Date` column (class `Date`, or POSIXct at daily
  resolution) and `MET_radswd` in W m-2.

- lat, lon:

  position in decimal degrees.

- tz:

  timezone the daily dates refer to, and in which the sub-daily output
  is labelled. Default `"Etc/GMT-12"` (fixed NZST, no daylight saving).

- timestep:

  `"hour"` (default) or `"3hour"`.

- interval:

  what a timestamp denotes: `"ending"` (default) means the value is the
  mean over the interval *ending* at that label, which is the convention
  of ERA5 accumulated fluxes and hence of
  [`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md);
  `"beginning"` is the mean over the following interval; `"instant"` is
  the instantaneous value at the label. Averaging over an interval is
  done on a 10-minute sub-grid, so sunrise and sunset steps are handled
  correctly.

- cloud:

  optional cloud fraction, scalar or one value per row of `met`, used to
  damp the clear-sky curve before rescaling (the rescale makes the daily
  total insensitive to this, but it changes the shape slightly).

## Value

data frame with `Date` (POSIXct in `tz`) and `MET_radswd` (W m-2). Days
whose clear-sky mean is zero (polar night) return zeros.

## Details

Unlike the equivalent routine in `AEME`, timestamps are handled
explicitly: daily dates are expanded into sub-daily steps *in `tz`*, the
solar geometry is evaluated at the corresponding UTC instants, and the
result is returned labelled in `tz`. The shortwave peak therefore lands
at local solar noon rather than being offset by the UTC offset.

## Examples

``` r
met <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day",
                             length.out = 5),
                  MET_radswd = c(300, 120, 280, 90, 310))
hr <- estimate_hourly_swr(met, lat = -38.08, lon = 176.27)
head(hr)
#>                  Date MET_radswd
#> 1 2024-01-01 00:00:00          0
#> 2 2024-01-01 01:00:00          0
#> 3 2024-01-01 02:00:00          0
#> 4 2024-01-01 03:00:00          0
#> 5 2024-01-01 04:00:00          0
#> 6 2024-01-01 05:00:00          0
```
