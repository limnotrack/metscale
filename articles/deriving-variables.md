# Deriving a complete met set

A lake model wants a dozen or more meteorological variables, but a
station or a reanalysis extract usually gives you five or six.
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
derives the rest from a small required core, filling in **only what is
missing**. This vignette shows
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
and then each of the underlying conversions on its own, because their
assumptions are what determine whether the derived values are any good.

``` r

library(metscale)
ex   <- system.file("extdata", package = "metscale")
lat  <- -38.0790
lon  <- 176.2717
elev <- 279          # Lake Rotorua surface, m
```

## `expand_met()`

The required core is: `MET_radswd` (W m-2), `MET_tmpair` (degC),
`MET_pprain` (mm per timestep), **one** of `MET_humrel` (%) or
`MET_tmpdew` (degC), and wind as either `MET_wndspd` or both
`MET_wnduvu` / `MET_wnduvv`. Take a minimal hourly slice:

``` r

era5 <- read.csv(file.path(ex, "rotorua_era5_hourly_met.csv.gz"), check.names = FALSE)
era5$Date <- as.POSIXct(era5$Date, tz = "Etc/GMT-12")

minimal <- era5[1:72, c("Date", "MET_radswd", "MET_tmpair", "MET_pprain",
                        "MET_humrel", "MET_wndspd")]
names(minimal)
#> [1] "Date"       "MET_radswd" "MET_tmpair" "MET_pprain" "MET_humrel" "MET_wndspd"
```

``` r

full <- expand_met(minimal, lat = lat, lon = lon, elev = elev,
                   tz = "Etc/GMT-12")
names(full)
#>  [1] "Date"       "MET_radswd" "MET_radlwd" "MET_cldcvr" "MET_tmpair" "MET_humrel"
#>  [7] "MET_tmpdew" "MET_prvapr" "MET_prsttn" "MET_prmslp" "MET_wndspd" "MET_wnddir"
#> [13] "MET_wnduvu" "MET_wnduvv" "MET_pprain" "MET_ppsnow"
setdiff(names(full), names(minimal))   # what expand_met() added
#>  [1] "MET_radlwd" "MET_cldcvr" "MET_tmpdew" "MET_prvapr" "MET_prsttn" "MET_prmslp"
#>  [7] "MET_wnddir" "MET_wnduvu" "MET_wnduvv" "MET_ppsnow"
```

Nothing is resampled and supplied columns are never overwritten — if you
pass `MET_cldcvr`, that is what comes back. `tz` is used only for the
solar geometry behind cloud cover, so pass the zone your `Date` column
is actually in.

## Humidity

Dew point, relative humidity and vapour pressure are three views of the
same quantity; give any one (plus air temperature) and the others
follow. `metscale` uses Magnus–Tetens with the Alduchov & Eskridge
coefficients.

``` r

airt <- c(5, 15, 25)
rh   <- c(90, 60, 40)

td <- rh_to_dewpoint(airt, rh)
td
#> [1]  3.495913  7.296691 10.465079
dewpoint_to_rh(airt, td)          # inverse
#> [1] 90 60 40
vapour_pressure(airt, rh)         # actual vapour pressure, hPa
#> [1]  7.851973 10.234601 12.675373
```

## Pressure

[`station_pressure()`](http://limnotrack.com/metscale/reference/station_pressure.md)
is the hypsometric equation with virtual temperature (it accounts for
the humidity dependence of air density), reducing a sea-level pressure
to the lake surface.
[`mslp_from_station()`](http://limnotrack.com/metscale/reference/mslp_from_station.md)
/
[`station_from_mslp()`](http://limnotrack.com/metscale/reference/mslp_from_station.md)
convert the other way.

``` r

ps <- station_pressure(airt = 12, relh = 80, elev = elev)   # Pa
ps
#> [1] 98007.82
mslp_from_station(ps, elev = elev, airt = 12)               # back to sea level
#> [1] 101329.2
```

This is why a raw ERA5-Land `MET_prsttn` can look ~3 kPa low at a lake:
the reanalysis reports pressure at its grid-cell orography height, which
is often a few hundred metres above the actual water surface. Supplying
the true `elev` to
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
(or bias-correcting the pressure) fixes it.

## Wind vector

[`ds2uv()`](http://limnotrack.com/metscale/reference/ds2uv.md) and
[`uv2ds()`](http://limnotrack.com/metscale/reference/uv2ds.md) are
mutual inverses using the meteorological convention — direction is where
the wind comes **from**.

``` r

uv <- ds2uv(d = 225, s = 5)      # SW wind at 5 m/s
uv
#>             u        v
#> [1,] 3.535534 3.535534
uv2ds(uv[, "u"], uv[, "v"])      # -> dir 225, speed 5
#>   dir speed
#> v 225     5
```

(The AEME port fixed a u/v swap here; `metscale`’s components are
consistent with its own speed/direction.) To move a measured wind
between sensor heights, use
[`wind_at_height()`](http://limnotrack.com/metscale/reference/wind_at_height.md)
/
[`met_wind_at_height()`](http://limnotrack.com/metscale/reference/met_wind_at_height.md)
— a 2 m buoy anemometer reads roughly 15–20% low against the 10 m
convention.

## Cloud cover from measured shortwave

[`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md)
inverts the ratio of measured to clear-sky potential shortwave: a bright
day implies little cloud, a dim one implies a lot. It needs the
timestamps, air temperature, dew point (or RH), position and `tz`.

``` r

cc <- calc_cc(minimal$Date, airt = minimal$MET_tmpair, swr = minimal$MET_radswd,
              relh = minimal$MET_humrel, lat = lat, lon = lon, elev = elev,
              tz = "Etc/GMT-12")
summary(cc)                       # 0-1 fraction
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>  0.4728  0.7679  0.9219  0.8609  0.9566  1.0000
```

Because it is a daytime ratio, night-time values are interpolated and a
day with no usable daylight (or with `MET_radswd` already an all-day
mean) gives a weak estimate.

## Longwave

[`calc_in_lwr()`](http://limnotrack.com/metscale/reference/calc_in_lwr.md)
builds downwelling longwave from a clear-sky emissivity (Idso & Jackson)
with a cloud correction:

``` r

calc_in_lwr(cc = c(0, 0.5, 1), airt = c(10, 10, 10), relh = c(80, 80, 80))
#> [1] 187.5103 229.5667 355.7359
```

## Solar geometry and shortwave

``` r

noon <- as.POSIXct("2024-01-15 13:00", tz = "Etc/GMT-12")
solar_zenith_angle(noon, lat = lat, lon = lon)            # degrees from vertical
#> [1] 19.57351
clear_sky_swr(noon, lat = lat, lon = lon)                 # W m-2, cloud-free
#> [1] 1014.316
```

[`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)
goes from a **daily-mean** `MET_radswd` to an hourly curve with real
night-time zeros, a peak at local solar noon, and each day’s mean
preserved:

``` r

day <- data.frame(Date = as.Date("2024-01-15") + 0:2,
                  MET_radswd = c(280, 120, 310))
hr  <- estimate_hourly_swr(day, lat = lat, lon = lon, tz = "Etc/GMT-12")

## recover the daily means -- aggregating in the SAME zone the series is
## labelled in; `as.Date()` defaults to UTC and would split days at the
## wrong instant
tapply(hr$MET_radswd, as.Date(hr$Date, tz = "Etc/GMT-12"), mean)   # == the inputs
#> 2024-01-15 2024-01-16 2024-01-17 
#>        280        120        310
hr[which.max(hr$MET_radswd), ]                                     # peak near local noon
#>                   Date MET_radswd
#> 62 2024-01-17 13:00:00   884.8689
```

## Three assumptions worth remembering

These are the behaviours `metscale` deliberately changed from the AEME
originals, because getting them wrong is silent:

- **Time zone.**
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md),
  [`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md) and
  [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)
  take an explicit `tz` and phase the solar geometry to it. Pass the
  zone your timestamps are in; the default is fixed NZST
  (`"Etc/GMT-12"`).
- **Pressure units.** Derived `MET_prsttn` / `MET_prmslp` are in **Pa**.
- **Wind components.**
  [`ds2uv()`](http://limnotrack.com/metscale/reference/ds2uv.md) /
  [`uv2ds()`](http://limnotrack.com/metscale/reference/uv2ds.md)
  round-trip; derived u/v are consistent with the speed/direction they
  came from.

## See also

- [`vignette("met-data-frames")`](http://limnotrack.com/metscale/articles/met-data-frames.md)
  — the names, units and time-zone convention these functions assume.
- [`vignette("scenario-workflow")`](http://limnotrack.com/metscale/articles/scenario-workflow.md)
  —
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  in a full projection pipeline, where it regenerates dependents after
  each adjustment.
