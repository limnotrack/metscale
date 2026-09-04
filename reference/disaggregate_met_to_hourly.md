# Disaggregate daily meteorology to hourly or 3-hourly

Distributes daily meteorology across the day using the diurnal structure
of an hourly reanalysis record for the same location, so that a daily
series - a bias-corrected daily record, or a climate-scenario series
from a delta-change step - can drive a sub-daily lake model. Daily means
(and daily rainfall totals) are conserved exactly, with one deliberate
exception: if the wind vector components `MET_wnduvu` / `MET_wnduvv` are
present they are shaped directly and `MET_wndspd` is recomputed from
them, so the disaggregated speed re-aggregates to the magnitude of the
daily *vector* mean rather than to a supplied daily *scalar* mean speed
(the former is the smaller of the two).

## Usage

``` r
disaggregate_met_to_hourly(
  daily,
  donor,
  method = c("fragments", "diurnal"),
  timestep = c("hour", "3hour"),
  swr = c("clearsky", "shape"),
  interval = c("ending", "beginning", "instant"),
  lat = NULL,
  lon = NULL,
  elev = 0,
  tz = NULL,
  analogue_window = 15,
  match_on_value = TRUE,
  sample_top_k = 1,
  blend_hours = 2,
  seed = NULL,
  expand = FALSE,
  verbose = TRUE
)
```

## Arguments

- daily:

  data frame with `Date` (class `Date`, or daily POSIXct) and `MET_*`
  columns. Rainfall and snowfall are treated as daily totals, every
  other variable as a daily mean.

- donor:

  hourly data frame with `Date` (POSIXct) and `MET_*` columns for the
  same location, e.g. from
  [`extract_era5_lake_met()`](http://limnotrack.com/metscale/reference/extract_era5_lake_met.md).
  A longer donor record gives a better analogue pool.

- method:

  `"fragments"` (default) or `"diurnal"`.

- timestep:

  `"hour"` (default) or `"3hour"`.

- swr:

  `"clearsky"` (default) to rebuild shortwave from solar geometry, or
  `"shape"` to treat it like any other multiplicative variable.
  `"clearsky"` needs `lat` and `lon`.

- interval:

  what a timestamp denotes, passed to
  [`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md).
  Default `"ending"`, matching the accumulated flux convention of ERA5
  and of
  [`extract_era5_hourly_met()`](http://limnotrack.com/metscale/reference/extract_era5_hourly_met.md).

- lat, lon:

  location in decimal degrees; taken from the `lat` / `lon` attributes
  of `daily` or `donor` when `NULL`.

- elev:

  elevation, m, used only when `expand = TRUE`.

- tz:

  timezone of `daily` and of the output. Defaults to the `tz` attribute
  of `daily`, then of `donor`, else `"Etc/GMT-12"`.

- analogue_window:

  half-width, in days of the year, of the donor pool for
  `method = "fragments"` (default 15).

- match_on_value:

  rank candidate donor days by similarity of their daily values, not
  just day-of-year (default `TRUE`).

- sample_top_k:

  sample the donor uniformly from the `k` best candidates instead of
  always taking the closest. `1` (default) is deterministic; larger
  values add realistic variety.

- blend_hours:

  smooth the borrowed shape across midnight over this many steps either
  side, to avoid a sawtooth discontinuity in temperature and humidity
  (default 2; `0` disables). Daily aggregates are restored afterwards,
  so conservation is unaffected. Never applied to rainfall or snowfall.

- seed:

  optional RNG seed, for reproducibility when `sample_top_k > 1`.

- expand:

  run
  [`expand_met()`](http://limnotrack.com/metscale/reference/expand_met.md)
  on the result to regenerate the dependent variables at the new
  timestep.

- verbose:

  print progress.

## Value

data frame with `Date` (POSIXct in `tz`, regular sub-daily steps) and
the same `MET_*` columns as `daily`. Attributes `tz`, `method`,
`timestep`, and `donor_days` (the analogue chosen for each target day,
`method = "fragments"` only).

## Details

Two ways of borrowing the structure:

- `"fragments"`:

  (default) the *method of fragments*: for each target day an analogue
  day is chosen from the donor record - close in day-of-year and, when
  `match_on_value`, close in daily values - and its within-day shape is
  applied to every variable at once. Because a single donor day supplies
  all variables, the temperature, humidity and wind sub-daily patterns
  stay mutually consistent, and day-to-day variability in the shape is
  retained.

- `"diurnal"`:

  a deterministic month-by-hour mean diurnal cycle from
  [`build_diurnal_climatology()`](http://limnotrack.com/metscale/reference/build_diurnal_climatology.md).
  Smoother and reproducible, but every day of a given month gets the
  same shape.

Shortwave radiation is handled separately and by default comes from
solar geometry
([`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md)),
which guarantees a single-peaked curve, true night-time zeros and a peak
at local solar noon. Rainfall in `"fragments"` mode borrows its shape
from a *wet* donor day, chosen by closeness of daily total, so that
wet-hour intermittency is preserved; a dry target day stays dry
throughout.

Variables present in `daily` but not in `donor` are held constant
through each day. Wind direction (`MET_wnddir`) is never shaped about a
daily mean - it is recomputed from the disaggregated `MET_wnduvu` /
`MET_wnduvv` when those are present, otherwise held constant per day.

## See also

[`build_diurnal_climatology()`](http://limnotrack.com/metscale/reference/build_diurnal_climatology.md),
[`estimate_hourly_swr()`](http://limnotrack.com/metscale/reference/estimate_hourly_swr.md),
[`met_to_daily()`](http://limnotrack.com/metscale/reference/met_to_daily.md)
for the reverse operation.

## Examples

``` r
set.seed(1)
## donor: two years of synthetic hourly data with a diurnal cycle
t <- seq(as.POSIXct("2022-01-01", tz = "Etc/GMT-12"), by = "hour",
         length.out = 24 * 730)
hr <- as.integer(format(t, "%H"))
donor <- data.frame(Date = t,
                    MET_tmpair = 15 + 5 * sin((hr - 9) / 24 * 2 * pi) + rnorm(length(t)),
                    MET_wndspd = pmax(0.1, 4 + 2 * sin((hr - 12) / 24 * 2 * pi)))
## daily series to disaggregate
daily <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 10),
                    MET_tmpair = rnorm(10, 16, 2),
                    MET_wndspd = runif(10, 2, 7))
out <- disaggregate_met_to_hourly(daily, donor, swr = "shape", verbose = FALSE)
head(out)
#>                  Date MET_tmpair MET_wndspd
#> 1 2024-01-01 00:00:00   13.15318   4.683362
#> 2 2024-01-01 01:00:00   12.49455   4.077291
#> 3 2024-01-01 02:00:00   13.52026   3.512522
#> 4 2024-01-01 03:00:00   12.11978   3.027544
#> 5 2024-01-01 04:00:00   12.80467   2.655407
#> 6 2024-01-01 05:00:00   14.34843   2.421472
```
