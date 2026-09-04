# Should a local bias correction be applied to climate scenario data?

Not to the change factors themselves. A delta-change projection supplies
a *difference* (or ratio) between two model climates, in which the
systematic model bias largely cancels; a reanalysis-to-observation
correction is an *absolute level* correction and does not belong on a
delta. Correct the baseline instead, then apply the delta on top:

## Details


    ERA5 hourly -> extract_era5_lake_met()
                -> fit_met_bias_correction(era5, obs)
                -> apply_met_bias_correction(full record)
                -> met_to_daily()                      # corrected baseline
                -> delta-change: extract_cmip6_point(), monthly change factors,
                   add / multiply onto the baseline
                -> disaggregate_met_to_hourly()        # if sub-daily is needed

See
[`vignette("scenario-workflow", package = "metscale")`](http://limnotrack.com/metscale/articles/scenario-workflow.md)
for a runnable end-to-end example on Lake Rotorua.

Applying the local correction to the baseline *before* the delta-change
step is what makes the composition well defined, whatever kinds the two
adjustments are: the NIWA CCAM change fields are additive in degC for
temperature, percentage for rainfall, wind and humidity, and additive in
W m-2 for shortwave, while
[`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md)
picks the transform per variable. Do not try to fold the local
correction in *after* the delta - correct first, shift second.

A caveat worth carrying: both steps assume stationarity. A correction
fitted over a few years of observations is being asserted to hold under
a future climate. Prefer `method = "scale"` over quantile mapping for a
baseline that will be projected, since a fitted CDF extrapolates poorly
outside its training range.

## See also

[`bias_correct_daily_baseline()`](http://limnotrack.com/metscale/reference/bias_correct_daily_baseline.md),
[`fit_met_bias_correction()`](http://limnotrack.com/metscale/reference/fit_met_bias_correction.md),
[`extract_cmip6_point()`](http://limnotrack.com/metscale/reference/extract_cmip6_point.md),
[`disaggregate_met_to_hourly()`](http://limnotrack.com/metscale/reference/disaggregate_met_to_hourly.md)
