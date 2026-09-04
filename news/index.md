# Changelog

## climprep 0.1.0

First release. `climprep` prepares model-ready meteorological forcing
from gridded reanalysis and climate projections: extract, bias-correct
against local observations, apply a climate-scenario delta change, and
temporally disaggregate to sub-daily. It works standalone and integrates
with `AEME` when that is installed. It carries the canonical
implementation of the meteorology helpers that previously lived in
`AEME`, with three long-standing defects fixed (time-zone handling in
the solar geometry, `MET_prsttn` / `MET_prmslp` returned in Pa not hPa,
and the u/v swap in
[`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)).

### Acquire ERA5

- [`download_era5_isimip_point()`](http://limnotrack.com/climprep/reference/download_era5_isimip_point.md)
  – daily ERA5 point series from ISIMIP3a, global, no account or key.
- [`download_era5_cds()`](http://limnotrack.com/climprep/reference/download_era5_cds.md)
  /
  [`read_era5_grib_point()`](http://limnotrack.com/climprep/reference/read_era5_grib_point.md)
  – hourly ERA5 GRIB from the Copernicus Data Store and point extraction
  from it.
- [`convert_era5_netcdf()`](http://limnotrack.com/climprep/reference/convert_era5_netcdf.md)
  – aggregate a downloaded ERA5 netCDF to daily.
- [`extract_era5_hourly_met()`](http://limnotrack.com/climprep/reference/extract_era5_hourly_met.md)
  /
  [`extract_era5_lake_met()`](http://limnotrack.com/climprep/reference/extract_era5_lake_met.md)
  – hourly ERA5-Land at a point or area-weighted over a lake polygon,
  de-accumulated, in standard units and a chosen time zone.

### Climate projections

- [`extract_cmip6_point()`](http://limnotrack.com/climprep/reference/extract_cmip6_point.md)
  – daily CMIP6 / CCAM projections at a point, decoding the model
  calendar (`365_day`, `360_day`, `366_day`, standard) and returning
  AEME `MET_*` names and units. Feeds the delta-change step.

### Observations

- [`prepare_obs_met()`](http://limnotrack.com/climprep/reference/prepare_obs_met.md)
  – standardise a measured meteorology table (names, units, time zone,
  resampling) for bias correction, with a `wind_height` argument to
  bring a low anemometer onto the 10 m convention.
- [`standardise_met()`](http://limnotrack.com/climprep/reference/standardise_met.md),
  [`guess_met_vars()`](http://limnotrack.com/climprep/reference/guess_met_vars.md),
  [`met_vars()`](http://limnotrack.com/climprep/reference/met_vars.md) –
  name/unit matching against a self-contained synonym table.

### Bias correction and delta change

- [`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md)
  – per-variable transfer function ERA5 -\> observations: per-month
  scaling (additive or ratio, optionally day-of-year loess-smoothed),
  variance scaling, linear regression, and empirical or trend-preserving
  quantile mapping, with leave-one-year-out cross-validation and a skill
  table.
- [`apply_met_bias_correction()`](http://limnotrack.com/climprep/reference/apply_met_bias_correction.md),
  [`met_to_daily()`](http://limnotrack.com/climprep/reference/met_to_daily.md),
  [`bias_correct_daily_baseline()`](http://limnotrack.com/climprep/reference/bias_correct_daily_baseline.md)
  – apply to the full record, aggregate to daily, and build the
  corrected baseline for a delta-change workflow.
- [`?scenario_workflow`](http://limnotrack.com/climprep/reference/scenario_workflow.md)
  – why the local correction goes on the baseline, not the delta.

### Temporal disaggregation

- [`disaggregate_met_to_hourly()`](http://limnotrack.com/climprep/reference/disaggregate_met_to_hourly.md)
  – daily meteorology (including climate-scenario series) to hourly or
  3-hourly by an analogue-day method of fragments or a mean diurnal
  cycle; daily means and rainfall totals are conserved, shortwave is
  rebuilt from solar geometry.
- [`build_diurnal_climatology()`](http://limnotrack.com/climprep/reference/build_diurnal_climatology.md)
  – the month-by-hour mean diurnal cycle.

### Conversions

- [`expand_met()`](http://limnotrack.com/climprep/reference/expand_met.md)
  – fill a minimal met set out to everything a lake model needs (dew
  point, vapour pressure, cloud cover, longwave, u/v, pressures,
  snowfall).
- [`met_to_cf()`](http://limnotrack.com/climprep/reference/met_to_cf.md)
  /
  [`cf_to_met()`](http://limnotrack.com/climprep/reference/cf_to_met.md)
  – translate a met table between the AEME `MET_*` scheme and CF / CMIP
  short names and units (`tas` K, `pr` kg m-2 s-1, `sfcWind`, `rsds`,
  …).
- [`wind_at_height()`](http://limnotrack.com/climprep/reference/wind_at_height.md)
  /
  [`met_wind_at_height()`](http://limnotrack.com/climprep/reference/met_wind_at_height.md)
  – adjust wind speed between measurement heights (neutral log profile,
  power law, or an iterative Charnock roughness), e.g. a 2 m buoy
  anemometer to 10 m.
- Humidity, wind-vector, pressure and longwave helpers:
  [`rh_to_dewpoint()`](http://limnotrack.com/climprep/reference/rh_to_dewpoint.md),
  [`dewpoint_to_rh()`](http://limnotrack.com/climprep/reference/dewpoint_to_rh.md),
  [`vapour_pressure()`](http://limnotrack.com/climprep/reference/vapour_pressure.md),
  [`calc_humidity_vars()`](http://limnotrack.com/climprep/reference/calc_humidity_vars.md),
  [`uv2ds()`](http://limnotrack.com/climprep/reference/uv2ds.md) /
  [`ds2uv()`](http://limnotrack.com/climprep/reference/ds2uv.md),
  [`station_pressure()`](http://limnotrack.com/climprep/reference/station_pressure.md),
  [`mslp_from_station()`](http://limnotrack.com/climprep/reference/mslp_from_station.md)
  /
  [`station_from_mslp()`](http://limnotrack.com/climprep/reference/mslp_from_station.md),
  [`calc_in_lwr()`](http://limnotrack.com/climprep/reference/calc_in_lwr.md),
  [`calc_cc()`](http://limnotrack.com/climprep/reference/calc_cc.md).
- Solar geometry:
  [`solar_zenith_angle()`](http://limnotrack.com/climprep/reference/solar_zenith_angle.md),
  [`clear_sky_swr()`](http://limnotrack.com/climprep/reference/clear_sky_swr.md),
  [`estimate_hourly_swr()`](http://limnotrack.com/climprep/reference/estimate_hourly_swr.md).

### Vignettes

- [`vignette("download-era5")`](http://limnotrack.com/climprep/articles/download-era5.md)
  – the three ways to acquire ERA5 forcing.
- [`vignette("scenario-workflow")`](http://limnotrack.com/climprep/articles/scenario-workflow.md)
  – the end-to-end bias-correction -\> delta-change -\> disaggregation
  pipeline on the bundled Lake Rotorua example data (precomputed).
