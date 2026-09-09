# Changelog

## metscale 0.1.0

First release. `metscale` prepares model-ready meteorological forcing
from gridded reanalysis and climate projections: extract, bias-correct
against local observations, apply a climate-scenario delta change, and
temporally disaggregate to sub-daily. It works standalone and integrates
with `AEME` when that is installed. It carries the canonical
implementation of the meteorology helpers that previously lived in
`AEME`, with three long-standing defects fixed (time-zone handling in
the solar geometry, `MET_prsttn` / `MET_prmslp` returned in Pa not hPa,
and the u/v swap in
[`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)).

### Acquire ERA5

- [`download_era5_isimip_point()`](http://limnotrack.com/metscale/reference/download_era5_isimip_point.md)
  – daily ERA5 point series from ISIMIP3a, global, no account or key.
- [`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)
  /
  [`read_era5_grib_point()`](http://limnotrack.com/metscale/reference/read_era5_grib_point.md)
  – hourly ERA5 GRIB from the Copernicus Data Store and point extraction
  from it.
- [`convert_era5_netcdf()`](http://limnotrack.com/metscale/reference/convert_era5_netcdf.md)
  – daily aggregation: a thin wrapper that runs
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  (so it now reads netCDF **or GRIB**, with the same `pattern` discovery
  and spatial sampling) and aggregates to daily with
  [`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md),
  adding daily min/max air and dewpoint temperature. Takes `path` first
  and forwards `...` to
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md);
  the old `year` / `variable` (singular) / positional `file` arguments
  are gone.
- [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  /
  [`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
  – hourly ERA5-Land at a point or area-weighted over a lake polygon,
  de-accumulated, in standard units and a chosen time zone.
  - Reads netCDF **or GRIB**; the backend is chosen per file from its
    extension (`.grib` / `.grb` / `.grib2` via `terra`, else `ncdf4`).
  - Files are found with `pattern`, a `{variable}` / `{year}` /
    `{month}` template matched against the names in `path` (replaces the
    old positional `file_template`; default `"{variable}"` covers
    [`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)
    output and most ad-hoc layouts).
  - `max_dist_km` (default 50) reports the distance to a `"nearest"`
    sample and errors if the closest valid cell is further away.
  - [`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
    now takes a lake polygon (an `sf`/`sfc` or a path to one) plus
    optional `id` / `name` labels; the old `lakes` / `layer` id-and-name
    lookup has been removed.
- [`plot_era5()`](http://limnotrack.com/metscale/reference/plot_era5.md)
  – a quick-look viewer for a downloaded ERA5 / ERA5-Land GRIB or netCDF
  file: for every variable it finds (GRIB bands grouped by
  `GRIB_ELEMENT`, netCDF by sub-dataset), a map of the field aggregated
  over time next to a time series – the grid mean, or a bilinear sample
  at `point`. `time` maps a single step instead; a vector of files is
  stacked in time. Returns a per-variable summary data frame with the
  aggregated maps and series attached, or a `ggplot` for
  `engine = "ggplot2"`. Reads with `terra`, matching the extractors’
  backend rule.
- [`plot_extract_grid()`](http://limnotrack.com/metscale/reference/plot_extract_grid.md)
  – a pre-extraction sanity-check map: the ERA5-Land grid around a point
  or lake polygon, the cell(s) each `method` would sample shaded by
  weight, the land/sea mask, and the geometry on top. Run it to catch a
  mis-projected shapefile or a sign-flipped longitude before extracting.
  Returns a `ggplot` (drawn cells attached as an `sf` on
  `attr(., "grid")` for handing to `mapview` / `tmap`), or draws with
  [`sf::plot()`](https://r-spatial.github.io/sf/reference/plot.html) for
  `engine = "base"`. Uses the same file-matching and sampling code as
  the extractors, so the preview cannot drift from the extraction.

### Climate projections

- [`extract_cmip6_point()`](http://limnotrack.com/metscale/reference/extract_cmip6_point.md)
  – daily CMIP6 / CCAM projections at a point, decoding the model
  calendar (`365_day`, `360_day`, `366_day`, standard) and returning
  AEME `MET_*` names and units. Feeds the delta-change step.

### Observations

- [`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md)
  – standardise a measured meteorology table (names, units, time zone,
  resampling) for bias correction, with a `wind_height` argument to
  bring a low anemometer onto the 10 m convention.
- [`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md),
  [`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md),
  [`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md) –
  name/unit matching against a self-contained synonym table.

### Bias correction and delta change

- [`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md)
  – per-variable transfer function ERA5 -\> observations: per-month
  scaling (additive or ratio, optionally day-of-year loess-smoothed),
  variance scaling, linear regression, and empirical or trend-preserving
  quantile mapping, with leave-one-year-out cross-validation and a skill
  table.
- [`apply_met_bias_correction()`](http://limnotrack.com/metscale/reference/apply_met_bias_correction.md),
  [`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md),
  [`bias_correct_daily_baseline()`](http://limnotrack.com/metscale/reference/bias_correct_daily_baseline.md)
  – apply to the full record, aggregate to daily, and build the
  corrected baseline for a delta-change workflow.
- [`?scenario_workflow`](http://limnotrack.com/metscale/reference/scenario_workflow.md)
  – why the local correction goes on the baseline, not the delta.

### Temporal disaggregation

- [`disaggregate_met_to_hourly()`](http://limnotrack.com/metscale/reference/disaggregate_met_to_hourly.md)
  – daily meteorology (including climate-scenario series) to hourly or
  3-hourly by an analogue-day method of fragments or a mean diurnal
  cycle; daily means and rainfall totals are conserved, shortwave is
  rebuilt from solar geometry.
- [`build_diurnal_climatology()`](http://limnotrack.com/metscale/reference/build_diurnal_climatology.md)
  – the month-by-hour mean diurnal cycle.

### Conversions

- [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  – fill a minimal met set out to everything a lake model needs (dew
  point, vapour pressure, cloud cover, longwave, u/v, pressures,
  snowfall).
- [`met_to_cf()`](http://limnotrack.com/metscale/reference/met_to_cf.md)
  /
  [`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md)
  – translate a met table between the AEME `MET_*` scheme and CF / CMIP
  short names and units (`tas` K, `pr` kg m-2 s-1, `sfcWind`, `rsds`,
  …).
- [`wind_at_height()`](http://limnotrack.com/metscale/reference/wind_at_height.md)
  /
  [`met_wind_at_height()`](http://limnotrack.com/metscale/reference/met_wind_at_height.md)
  – adjust wind speed between measurement heights (neutral log profile,
  power law, or an iterative Charnock roughness), e.g. a 2 m buoy
  anemometer to 10 m.
- Humidity, wind-vector, pressure and longwave helpers:
  [`rh_to_dewpoint()`](http://limnotrack.com/metscale/reference/rh_to_dewpoint.md),
  [`dewpoint_to_rh()`](http://limnotrack.com/metscale/reference/dewpoint_to_rh.md),
  [`vapour_pressure()`](http://limnotrack.com/metscale/reference/vapour_pressure.md),
  [`calc_humidity_vars()`](http://limnotrack.com/metscale/reference/calc_humidity_vars.md),
  [`uv2ds()`](http://limnotrack.com/metscale/reference/uv2ds.md) /
  [`ds2uv()`](http://limnotrack.com/metscale/reference/ds2uv.md),
  [`station_pressure()`](http://limnotrack.com/metscale/reference/station_pressure.md),
  [`mslp_from_station()`](http://limnotrack.com/metscale/reference/mslp_from_station.md)
  /
  [`station_from_mslp()`](http://limnotrack.com/metscale/reference/mslp_from_station.md),
  [`calc_in_lwr()`](http://limnotrack.com/metscale/reference/calc_in_lwr.md),
  [`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md).
- Solar geometry:
  [`solar_zenith_angle()`](http://limnotrack.com/metscale/reference/solar_zenith_angle.md),
  [`clear_sky_swr()`](http://limnotrack.com/metscale/reference/clear_sky_swr.md),
  [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md).

### Time zones

- Every function that takes a `tz` argument now defaults to **UTC**, the
  zone ERA5, ERA5-Land and CMIP6 are published in, instead of the
  New-Zealand-specific `"Etc/GMT-12"`.
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md)
  /
  [`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md)
  therefore return the reanalysis on its native clock with no hidden
  shift; convert downstream by passing `tz` (e.g. `"Etc/GMT-12"` for
  fixed NZST) or with
  [`lubridate::with_tz()`](https://lubridate.tidyverse.org/reference/with_tz.html).
- `tz` is resolved consistently across the package: an explicit argument
  wins, otherwise the `tz` attribute carried on the input data frame (or
  a POSIXct’s `tzone`), otherwise UTC.
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md),
  [`calc_cc()`](http://limnotrack.com/metscale/reference/calc_cc.md) and
  [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)
  previously ignored that attribute and hard-coded `"Etc/GMT-12"`, which
  could re-introduce the solar phase-shift on non-NZ input; they now
  follow the attribute like the rest.

### Vignettes

- [`vignette("met-data-frames")`](http://limnotrack.com/metscale/articles/met-data-frames.md)
  – the `MET_*` names, units and time-zone convention, and the helpers
  ([`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md),
  [`prepare_obs_met()`](http://limnotrack.com/metscale/reference/prepare_obs_met.md),
  [`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md),
  [`met_to_cf()`](http://limnotrack.com/metscale/reference/met_to_cf.md)
  /
  [`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md))
  that bring data into it.
- [`vignette("download-era5")`](http://limnotrack.com/metscale/articles/download-era5.md)
  – the three ways to acquire ERA5 forcing.
- [`vignette("extract-era5-lake")`](http://limnotrack.com/metscale/articles/extract-era5-lake.md)
  – point vs polygon (lake-average) extraction from ERA5-Land netCDF and
  the `method` options, with
  [`plot_extract_grid()`](http://limnotrack.com/metscale/reference/plot_extract_grid.md)
  worked through for each: a point, the four polygon methods side by
  side, cells masked by ERA5-Land, and `max_dist_km`.
- [`vignette("deriving-variables")`](http://limnotrack.com/metscale/articles/deriving-variables.md)
  – fill a minimal set out to everything a lake model needs with
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  and the underlying conversions.
- [`vignette("bias-correction-methods")`](http://limnotrack.com/metscale/articles/bias-correction-methods.md)
  – comparing `scale` / `variance` / `eqm` / `qdm`, reading the
  cross-validated skill table, and the present-day vs projection
  trade-off.
- [`vignette("scenario-workflow")`](http://limnotrack.com/metscale/articles/scenario-workflow.md)
  – the end-to-end bias-correction -\> delta-change -\> disaggregation
  pipeline on the bundled Lake Rotorua example data, with an appendix on
  checking the extraction grid with
  [`plot_extract_grid()`](http://limnotrack.com/metscale/reference/plot_extract_grid.md).
