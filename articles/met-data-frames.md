# Meteorology data frames: names, units, time zones

Every `metscale` function reads and returns the same shape of object: a
data frame with a `Date` column and one column per meteorological
variable, named and unitised by a fixed convention. This vignette covers
that convention and the helpers that bring an arbitrary table into it.

``` r

library(metscale)
ex <- system.file("extdata", package = "metscale")
```

## The `MET_*` scheme

Columns follow the AEME `MET_*` names.
[`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md) is
the full list with units:

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

A few points that trip people up:

- **Rainfall and snowfall are per-timestep totals**, not rates — `mm` in
  an hourly frame means mm/hour, `mm` in a daily frame means mm/day.
  Every other variable is an instantaneous value (or an interval mean).
- **Pressure is in pascals.** `MET_prsttn` (station) and `MET_prmslp`
  (sea level) are Pa, not hPa. Vapour pressure `MET_prvapr` is the
  exception — hPa.
- **Wind direction is the direction the wind blows *from***, degrees
  clockwise from north, and `MET_wnduvu` / `MET_wnduvv` are the matching
  eastward / northward components.
- **Cloud cover is a 0–1 fraction**, not oktas or percent.

## Matching arbitrary names: `guess_met_vars()`

[`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md)
maps logger / council / NIWA / ERA5 / CMIP column names onto `MET_*` by
case-insensitive pattern, returning `NA` where nothing fits:

``` r

guess_met_vars(c("AirTemp_C", "WindSpd", "RH_pct", "SolarRad_Wm2",
                 "rain_mm", "t2m", "sfcWind", "junk_column"))
#> [1] "MET_tmpair" "MET_wndspd" NA           "MET_radswd" "MET_pprain" "MET_tmpair"
#> [7] "MET_wndspd" NA
```

## Standardising a whole table: `standardise_met()`

[`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md)
renames with
[`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md)
**and** repairs the common unit mistakes it can detect from the value
ranges (Kelvin, hPa, humidity as a fraction, oktas, km/h, precipitation
in metres, radiation in MJ m-2 day-1). It finds the date column itself
and renames it `Date`.

``` r

raw <- data.frame(
  timestamp   = as.Date("2024-01-01") + 0:4,
  AirTemp_K   = c(291, 289, 292, 288, 293),
  WindSpd_kmh = c(11, 18, 7, 22, 11),
  SolarRad    = c(300, 120, 280, 90, 310),
  RH          = c(0.72, 0.85, 0.61, 0.90, 0.55),
  Rain_mm     = c(0, 12, 0, 25, 0))

std <- standardise_met(raw)
#> date column: timestamp -> Date
#> renamed: AirTemp_K -> MET_tmpair, WindSpd_kmh -> MET_wndspd, SolarRad -> MET_radswd, RH -> MET_humrel, Rain_mm -> MET_pprain
#> MET_tmpair: K -> degC
#> MET_humrel: fraction -> %
std
#>         Date MET_tmpair MET_wndspd MET_radswd MET_humrel MET_pprain
#> 1 2024-01-01      17.85         11        300         72          0
#> 2 2024-01-02      15.85         18        120         85         12
#> 3 2024-01-03      18.85          7        280         61          0
#> 4 2024-01-04      14.85         22         90         90         25
#> 5 2024-01-05      19.85         11        310         55          0
```

The messages say what it did; pass `verbose = FALSE` to silence them.
Columns it cannot match are kept unchanged and warned about, so nothing
is lost silently. It does **not** resample or derive missing variables —
that is
[`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md)
and
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md).

## Preparing observations: `prepare_obs_met()`

For a *measured* series destined for bias correction,
[`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md)
wraps
[`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md)
and adds the steps that matter for lining the observations up with
reanalysis:

``` r

obs <- prepare_obs_met(file.path(ex, "rotorua_buoy_met_aeme_hr.csv.gz"),
                       resample    = "hour",   # bin sub-hourly records to whole hours
                       tz          = "Etc/GMT-12",
                       wind_height = 2,        # 2 m buoy anemometer -> 10 m
                       station     = "rotorua_buoy",
                       verbose     = FALSE)
str(obs, give.attr = FALSE)
#> 'data.frame':    25082 obs. of  11 variables:
#>  $ Date      : POSIXct, format: "2023-01-01 01:00:00" "2023-01-01 02:00:00" ...
#>  $ MET_tmpair: num  14.1 14 13.8 13.6 13.5 ...
#>  $ MET_wnddir: num  119 115 124 119 128 ...
#>  $ MET_prsttn: num  99030 98990 98970 98980 99000 ...
#>  $ MET_wndspd: num  10.68 9.38 9.51 8.39 8.05 ...
#>  $ MET_humrel: num  71.8 70 71.2 72.6 76.3 ...
#>  $ MET_radswd: num  0 0 0 0.03 24.21 ...
#>  $ MET_pprain: num  0 0 0 0 0 0 0 0 0 0 ...
#>  $ MET_wnduvu: num  -9.36 -8.49 -7.86 -7.34 -6.31 ...
#>  $ MET_wnduvv: num  5.13 3.99 5.36 4.07 5 ...
#>  $ MET_tmpdew: num  9.11 8.6 8.67 8.77 9.4 ...
attributes(obs)[c("tz", "resolution", "station")]
#> $tz
#> [1] "Etc/GMT-12"
#> 
#> $resolution
#> [1] "hourly"
#> 
#> $station
#> [1] "rotorua_buoy"
```

What it adds over
[`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md):

- reads a `.csv` / `.csv.gz` / `.rds` path directly;
- `resample = "hour"` / `"day"` — means for most variables, **sums** for
  rain and snow;
- `interval = "ending"` (default) labels a sub-hourly record by the hour
  it *ends* in, matching ERA5’s accumulated-flux convention so the two
  join cleanly on `Date`;
- `derive = TRUE` fills `MET_wndspd`/`MET_wnddir` ↔︎ u/v and `MET_humrel`
  ↔︎ `MET_tmpdew` when one side is present;
- `wind_height` rescales a low anemometer to the 10 m convention
  (\[[`wind_at_height()`](http://limnotrack.com/metscale/reference/wind_at_height.md)\])
  — a buoy at 2 m reads roughly 15–20% low;
- records `tz`, `resolution` and `station` as attributes, which
  [`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md)
  carries into its metadata.

## Time zone

Every `tz` argument defaults to `"UTC"` — the clock ERA5, ERA5-Land and
CMIP6 are published on — and resolves the same way everywhere: an
explicit value first, then the `tz` attribute carried on the input frame
(so a zone set once on the extractor output flows through the pipeline),
then UTC. The extractors therefore return the reanalysis with no hidden
shift.

To work in local time, pass the zone your timestamps are in. Prefer a
**fixed** offset such as `"Etc/GMT-12"` (NZST, UTC+12, no daylight
saving): it keeps a gap-free regular sub-daily series, whereas civil
time with DST has a missing hour in spring and a doubled hour in autumn
that breaks a strict hourly index. Use `"Pacific/Auckland"` only if your
logger recorded civil time and you need it back in civil time.

The zone is not cosmetic:
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md),
[`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md) and
[`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)
evaluate the solar geometry at the matching UTC instants, so with a
local `tz` the shortwave peak lands at local solar noon. (The AEME
versions of these routines forced the session zone to UTC and read the
wall clock, shifting the solar curve by the UTC offset — 12 h for New
Zealand. `metscale` fixes that; pass the zone your timestamps are
actually in.)

## Daily aggregation: `met_to_daily()`

[`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md)
collapses an hourly (or finer) frame to daily — means for everything
except rain and snow, which are summed — and returns `Date` as class
`Date`. `min_frac` drops days that are too incomplete to trust.

``` r

era5 <- read.csv(file.path(ex, "rotorua_era5_hourly_met.csv.gz"), check.names = FALSE)
era5$Date <- as.POSIXct(era5$Date, tz = "Etc/GMT-12")

daily <- met_to_daily(era5, tz = "Etc/GMT-12", min_frac = 0.9)
head(daily[, c("Date", "MET_tmpair", "MET_wndspd", "MET_pprain")])
#>         Date MET_tmpair MET_wndspd MET_pprain
#> 1 2023-12-02   12.54796   1.823708     0.0717
#> 2 2023-12-03   12.85358   2.906167    12.2033
#> 3 2023-12-04   15.25296   1.435000    24.5924
#> 4 2023-12-05   11.59625   3.096333     0.7414
#> 5 2023-12-06   13.59750   1.599542     2.7446
#> 6 2023-12-07   15.56450   2.098000     0.1551
```

## Handing data to CF / CMIP tools: `met_to_cf()` / `cf_to_met()`

[`met_to_cf()`](http://limnotrack.com/metscale/reference/met_to_cf.md)
renames the `MET_*` columns to the CF / CMIP short names (`tas`, `pr`,
`sfcWind`, `rsds`, …) and converts each to its CF-canonical unit;
[`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md)
is the exact inverse. The precipitation conversion needs a timestep (mm
per step ↔︎ `kg m-2 s-1`), inferred from the time column or passed as
`timestep`.

``` r

cf <- met_to_cf(daily[, c("Date", "MET_tmpair", "MET_wndspd", "MET_pprain")])
head(cf)
#>         time      tas  sfcWind           pr
#> 1 2023-12-02 285.6980 1.823708 8.298611e-07
#> 2 2023-12-03 286.0036 2.906167 1.412419e-04
#> 3 2023-12-04 288.4030 1.435000 2.846343e-04
#> 4 2023-12-05 284.7462 3.096333 8.581019e-06
#> 5 2023-12-06 286.7475 1.599542 3.176620e-05
#> 6 2023-12-07 288.7145 2.098000 1.795139e-06
attr(cf, "cf_units")
#>          tas      sfcWind           pr 
#>          "K"      "m s-1" "kg m-2 s-1"

back <- cf_to_met(cf)
head(back)
#>         Date MET_tmpair MET_wndspd MET_pprain
#> 1 2023-12-02   12.54796   1.823708     0.0717
#> 2 2023-12-03   12.85358   2.906167    12.2033
#> 3 2023-12-04   15.25296   1.435000    24.5924
#> 4 2023-12-05   11.59625   3.096333     0.7414
#> 5 2023-12-06   13.59750   1.599542     2.7446
#> 6 2023-12-07   15.56450   2.098000     0.1551
## round-trips to within floating point
max(abs(back$MET_pprain - daily$MET_pprain))
#> [1] 7.105427e-15
```

`era5_ref_table` is the underlying variable / unit / daily-aggregation
map across ERA5, LakeEnsemblR and AEME:

``` r

era5_ref_table
#>                           variable                                era5   nc
#> 1                             Time                                time time
#> 2                  Air temperature                      2m_temperature  t2m
#> 3             Dewpoint temperature             2m_dewpoint_temperature  d2m
#> 4             Wind u-vector at 10m             10m_u_component_of_wind  u10
#> 5             Wind v-vector at 10m             10m_v_component_of_wind  v10
#> 6              Total precipitation                 total_precipitation   tp
#> 7                         Snowfall                            snowfall   sf
#> 8           Surface level pressure                    surface_pressure   sp
#> 9  Downwelling shortwave radiation   surface_solar_radiation_downwards ssrd
#> 10  Downwelling longwave radiation surface_thermal_radiation_downwards strd
#>                                                    ler       aeme nc_unit agg_fun
#> 1                                             datetime       Date    Date    mean
#> 2                              Air_Temperature_celsius MET_tmpair       K    mean
#> 3                         Dewpoint_Temperature_celsius MET_tmpdew       K    mean
#> 4                Ten_Meter_Uwind_vector_meterPerSecond MET_wnduvu  m s**1    mean
#> 5                Ten_Meter_Vwind_vector_meterPerSecond MET_wnduvv  m s**1    mean
#> 6                      Precipitation_millimeterPerHour MET_pprain       m     sum
#> 7                           Snowfall_millimeterPerHour MET_ppsnow       m     sum
#> 8             Surface_Level_Barometric_Pressure_pascal MET_prsttn      Pa    mean
#> 9  Shortwave_Radiation_Downwelling_wattPerMeterSquared MET_radswd J m**-2    mean
#> 10  Longwave_Radiation_Downwelling_wattPerMeterSquared MET_radlwd J m**-2    mean
```

## See also

- [`vignette("deriving-variables")`](http://limnotrack.com/metscale/articles/deriving-variables.md)
  — fill a minimal set out to everything a lake model needs with
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md).
- [`vignette("bias-correction-methods")`](http://limnotrack.com/metscale/articles/bias-correction-methods.md)
  — correct a standardised ERA5 frame against a
  [`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md)
  frame.
- [`vignette("scenario-workflow")`](http://limnotrack.com/metscale/articles/scenario-workflow.md)
  — the full bias-correction → delta-change → disaggregation pipeline.
