# climprep 0.1.0

First release. `climprep` prepares model-ready meteorological forcing from
gridded reanalysis and climate projections: extract, bias-correct against
local observations, apply a climate-scenario delta change, and temporally
disaggregate to sub-daily. It works standalone and integrates with `AEME`
when that is installed. It carries the canonical implementation of the
meteorology helpers that previously lived in `AEME`, with three long-standing
defects fixed (time-zone handling in the solar geometry, `MET_prsttn` /
`MET_prmslp` returned in Pa not hPa, and the u/v swap in `expand_met()`).

## Acquire ERA5

* `download_era5_isimip_point()` -- daily ERA5 point series from ISIMIP3a,
  global, no account or key.
* `download_era5_cds()` / `read_era5_grib_point()` -- hourly ERA5 GRIB from
  the Copernicus Data Store and point extraction from it.
* `convert_era5_netcdf()` -- aggregate a downloaded ERA5 netCDF to daily.
* `extract_era5_hourly_met()` / `extract_era5_lake_met()` -- hourly
  ERA5-Land at a point or area-weighted over a lake polygon, de-accumulated,
  in standard units and a chosen time zone.

## Climate projections

* `extract_cmip6_point()` -- daily CMIP6 / CCAM projections at a point,
  decoding the model calendar (`365_day`, `360_day`, `366_day`, standard)
  and returning AEME `MET_*` names and units. Feeds the delta-change step.

## Observations

* `prepare_obs_met()` -- standardise a measured meteorology table (names,
  units, time zone, resampling) for bias correction, with a `wind_height`
  argument to bring a low anemometer onto the 10 m convention.
* `standardise_met()`, `guess_met_vars()`, `met_vars()` -- name/unit
  matching against a self-contained synonym table.

## Bias correction and delta change

* `fit_met_bias_correction()` -- per-variable transfer function
  ERA5 -> observations: per-month scaling (additive or ratio, optionally
  day-of-year loess-smoothed), variance scaling, linear regression, and
  empirical or trend-preserving quantile mapping, with leave-one-year-out
  cross-validation and a skill table.
* `apply_met_bias_correction()`, `met_to_daily()`,
  `bias_correct_daily_baseline()` -- apply to the full record, aggregate to
  daily, and build the corrected baseline for a delta-change workflow.
* `?scenario_workflow` -- why the local correction goes on the baseline, not
  the delta.

## Temporal disaggregation

* `disaggregate_met_to_hourly()` -- daily meteorology (including
  climate-scenario series) to hourly or 3-hourly by an analogue-day method
  of fragments or a mean diurnal cycle; daily means and rainfall totals are
  conserved, shortwave is rebuilt from solar geometry.
* `build_diurnal_climatology()` -- the month-by-hour mean diurnal cycle.

## Conversions

* `expand_met()` -- fill a minimal met set out to everything a lake model
  needs (dew point, vapour pressure, cloud cover, longwave, u/v, pressures,
  snowfall).
* `met_to_cf()` / `cf_to_met()` -- translate a met table between the AEME
  `MET_*` scheme and CF / CMIP short names and units (`tas` K, `pr`
  kg m-2 s-1, `sfcWind`, `rsds`, ...).
* `wind_at_height()` / `met_wind_at_height()` -- adjust wind speed between
  measurement heights (neutral log profile, power law, or an iterative
  Charnock roughness), e.g. a 2 m buoy anemometer to 10 m.
* Humidity, wind-vector, pressure and longwave helpers: `rh_to_dewpoint()`,
  `dewpoint_to_rh()`, `vapour_pressure()`, `calc_humidity_vars()`,
  `uv2ds()` / `ds2uv()`, `station_pressure()`, `mslp_from_station()` /
  `station_from_mslp()`, `calc_in_lwr()`, `calc_cc()`.
* Solar geometry: `solar_zenith_angle()`, `clear_sky_swr()`,
  `estimate_hourly_swr()`.

## Vignettes

* `vignette("download-era5")` -- the three ways to acquire ERA5 forcing.
* `vignette("scenario-workflow")` -- the end-to-end bias-correction ->
  delta-change -> disaggregation pipeline on the bundled Lake Rotorua
  example data (precomputed).
