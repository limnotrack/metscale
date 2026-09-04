# metscale

Model-ready meteorological forcing from gridded reanalysis and climate
projections, bias-corrected against local observations and temporally
disaggregated. `metscale` covers the meteorological side of
process-model forcing without depending on any model: extract, correct,
disaggregate, and a set of clean meteorological conversions. It
integrates with the Aquatic Ecosystem Model Ensemble
([`AEME`](https://github.com/limnotrack/AEME)) when that is installed,
but does not require it.

## What it does

| Task | Function |
|----|----|
| Download ERA5 forcing: global daily point series (ISIMIP3a, no key), hourly GRIB from the Copernicus Data Store, or aggregate downloaded netCDF to daily | [`download_era5_isimip_point()`](http://limnotrack.com/metscale/reference/download_era5_isimip_point.md), [`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md) / [`read_era5_grib_point()`](http://limnotrack.com/metscale/reference/read_era5_grib_point.md), [`convert_era5_netcdf()`](http://limnotrack.com/metscale/reference/convert_era5_netcdf.md) |
| Extract hourly ERA5-Land at a point or averaged over a lake polygon, in standard units and time zone | [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md), [`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md) |
| Standardise a table of measured meteorology (names, units, timezone, resampling) | [`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md), [`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md), [`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md) |
| Translate a met table between the AEME `MET_*` scheme and CF / CMIP short names and units (`tas`, `pr`, `sfcWind`, …) | [`met_to_cf()`](http://limnotrack.com/metscale/reference/met_to_cf.md), [`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md) |
| Fit a bias correction ERA5 -\> observations (monthly scaling, variance scaling, regression, empirical / trend-preserving quantile mapping) with leave-one-year-out cross-validation | [`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md) |
| Apply it to the full record and aggregate to daily | [`apply_met_bias_correction()`](http://limnotrack.com/metscale/reference/apply_met_bias_correction.md), [`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md) |
| Build a bias-corrected daily baseline for a climate-scenario (delta-change) workflow | [`bias_correct_daily_baseline()`](http://limnotrack.com/metscale/reference/bias_correct_daily_baseline.md), [`?scenario_workflow`](http://limnotrack.com/metscale/reference/scenario_workflow.md) |
| Read daily CMIP6 / CCAM projections at a point (model-calendar aware) for the delta-change step | [`extract_cmip6_point()`](http://limnotrack.com/metscale/reference/extract_cmip6_point.md) |
| Disaggregate daily meteorology to hourly / 3-hourly (method of fragments or mean diurnal cycle) | [`disaggregate_met_to_hourly()`](http://limnotrack.com/metscale/reference/disaggregate_met_to_hourly.md), [`build_diurnal_climatology()`](http://limnotrack.com/metscale/reference/build_diurnal_climatology.md) |
| Fill a minimal met set out to everything a lake model needs | [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md) |
| Solar geometry, clear-sky shortwave, hourly shortwave from daily | [`solar_zenith_angle()`](http://limnotrack.com/metscale/reference/solar_zenith_angle.md), [`clear_sky_swr()`](http://limnotrack.com/metscale/reference/clear_sky_swr.md), [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md) |
| Adjust wind speed between measurement heights (e.g. a 2 m buoy anemometer to the 10 m reanalysis / lake-model convention) | [`wind_at_height()`](http://limnotrack.com/metscale/reference/wind_at_height.md), [`met_wind_at_height()`](http://limnotrack.com/metscale/reference/met_wind_at_height.md) |
| Humidity, wind-vector, pressure and longwave conversions | [`rh_to_dewpoint()`](http://limnotrack.com/metscale/reference/rh_to_dewpoint.md), [`uv2ds()`](http://limnotrack.com/metscale/reference/uv2ds.md) / [`ds2uv()`](http://limnotrack.com/metscale/reference/ds2uv.md), [`station_pressure()`](http://limnotrack.com/metscale/reference/station_pressure.md), [`calc_in_lwr()`](http://limnotrack.com/metscale/reference/calc_in_lwr.md), [`calc_humidity_vars()`](http://limnotrack.com/metscale/reference/calc_humidity_vars.md), [`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md) |

## Standard variables

Columns follow the AEME `MET_*` scheme
([`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md)):
`MET_radswd` W/m2, `MET_radlwd` W/m2, `MET_cldcvr` fraction,
`MET_tmpair` degC, `MET_humrel` %, `MET_tmpdew` degC, `MET_prvapr` hPa,
`MET_prsttn` / `MET_prmslp` Pa, `MET_wndspd` m/s, `MET_wnddir` degrees
(from), `MET_wnduvu` / `MET_wnduvv` m/s, `MET_pprain` / `MET_ppsnow` mm
per timestep.

The default time zone `"Etc/GMT-12"` is fixed NZST (UTC+12, no daylight
saving), which keeps a gap-free regular sub-daily series; pass any other
zone via the `tz` argument.

[`met_to_cf()`](http://limnotrack.com/metscale/reference/met_to_cf.md)
maps this scheme onto the CF / CMIP short names and units (`MET_tmpair`
degC → `tas` K, `MET_pprain` mm/step → `pr` kg m-2 s-1, `MET_wndspd` →
`sfcWind`, `MET_radswd` → `rsds`, …) for handing data to tools that
expect that vocabulary;
[`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md)
is the inverse.

## Relationship to AEME

`metscale` holds the canonical implementation of the meteorology helpers
that previously lived inside `AEME` (`expand_met`, `standardise_met`,
`calc_cc`, `calc_in_lwr`, `calc_swr` / `estimate_hourly_swr`, the
humidity, wind and pressure conversions). Three long-standing defects
were fixed on the way across:

- **Time zone.**
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  / [`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md) /
  [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)
  take an explicit `tz`. The `AEME` versions force the session time zone
  to UTC and read the wall clock, which shifts the solar-geometry curve
  by the UTC offset (12 h for New Zealand) whenever the input is a local
  POSIXct.
- **Pressure units.**
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  returns `MET_prsttn` / `MET_prmslp` in Pa. `AEME`’s station-pressure
  helper returned hPa despite the documented unit, so an expanded set
  with no supplied pressure came out a factor of 100 low.
- **Wind components.**
  [`ds2uv()`](http://limnotrack.com/metscale/reference/ds2uv.md) /
  [`uv2ds()`](http://limnotrack.com/metscale/reference/uv2ds.md) are
  mutual inverses using the meteorological “direction from” convention.
  [`AEME::expand_met()`](https://limnotrack.com/reference/expand_met.html)
  swapped u and v when deriving components from speed and direction.

## Example

Runs on the bundled Lake Rotorua sample data (three years of hourly
ERA5-Land, the matching buoy record, and daily CMIP6 / CCAM
projections).

``` r

library(metscale)
ex <- system.file("extdata", package = "metscale")

era5 <- read.csv(file.path(ex, "rotorua_era5_hourly_met.csv.gz"), check.names = FALSE)
era5$Date <- as.POSIXct(era5$Date, tz = "Etc/GMT-12")
obs  <- prepare_obs_met(file.path(ex, "rotorua_buoy_met_aeme_hr.csv.gz"),
                        resample = "hour", tz = "Etc/GMT-12",
                        wind_height = 2)   # buoy anemometer at 2 m -> 10 m

## 1. bias-correct ERA5 against the buoy, apply, aggregate to daily
bc        <- fit_met_bias_correction(era5, obs)   # leave-one-year-out CV
bc$skill
corrected <- apply_met_bias_correction(era5, bc)
daily     <- met_to_daily(corrected)

## 2. daily CMIP6 projections at the lake (input to the delta-change baseline)
cmip <- extract_cmip6_point(file.path(ex, "rotorua_cmip6"),
                            lon = 176.2717, lat = -38.0790)

## 3. disaggregate a daily series back to hourly for a sub-daily model
hourly <- disaggregate_met_to_hourly(daily, donor = corrected, method = "fragments",
                                     lon = 176.2717, lat = -38.0790)

## 4. hand off in CF / CMIP names and units: tas [K], pr [kg m-2 s-1], ...
cf <- met_to_cf(hourly)
```

The full bias-correction → delta-change → disaggregation workflow is
walked through in
[`vignette("scenario-workflow")`](http://limnotrack.com/metscale/articles/scenario-workflow.md).

## Installation

``` r

# install.packages("pak")
pak::pak("limnotrack/metscale")
```
