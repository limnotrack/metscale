# Equal-weighted monthly climatology from CMIP6 / CCAM point files

Companion to
[`extract_climate_point()`](http://limnotrack.com/metscale/reference/extract_climate_point.md),
for building the monthly delta-change factors of
[scenario_workflow](http://limnotrack.com/metscale/reference/scenario_workflow.md).
[`extract_climate_point()`](http://limnotrack.com/metscale/reference/extract_climate_point.md)
merges variables onto a shared `Date` and, to do that safely, averages
together any model-days a fixed-length calendar's month-end clamp maps
onto the same real date (see its documentation) - which very slightly
down-weights those clamped days in a monthly mean taken from its output,
since they then count as a single row instead of several. This function
instead reads each variable's own per-file series independently and
averages straight by calendar month, before any Date-based merge or
clamp-collapse happens, so every model day counts equally regardless of
how many (or how few) real dates it lands on.

## Usage

``` r
climate_point_monthly_climatology(
  path,
  lon,
  lat,
  vars = c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd", "MET_humrel",
    "MET_radlwd", "MET_prsttn"),
  experiments = NULL,
  method = c("bilinear", "nearest"),
  calendar = c("auto", "365_day", "360_day", "366_day", "standard"),
  years = NULL,
  fun = mean,
  verbose = TRUE
)
```

## Arguments

- path:

  directory holding the `.nc` files, or a character vector of file
  paths.

- lon, lat:

  point of interest, decimal degrees (WGS84).

- vars:

  variables to return, as AEME `MET_*` names or CMIP short names (do not
  mix the two). Default is the seven mapped variables; only those
  present on disk are returned.

- experiments:

  optional character vector to keep (e.g. `c("historical", "ssp245")`);
  `NULL` (default) returns every experiment found.

- method:

  `"bilinear"` (default) interpolation between the four surrounding grid
  nodes, or `"nearest"` grid node.

- calendar:

  `"auto"` (default, read from the `time` variable's `calendar`
  attribute), or force one of `"365_day"`, `"360_day"`, `"366_day"`,
  `"standard"`. A `365_day` / `360_day` series is mapped onto real
  dates, so it has no 29 February (and, for `360_day`, no 31st).

- years:

  optional integer vector of calendar years (as decoded onto real dates)
  to include, e.g. a historical or future reference window. `NULL`
  (default) uses every year found.

- fun:

  the averaging function applied per experiment/variable/month. Default
  `mean`.

- verbose:

  print each file as it is read.

## Value

a data frame with `experiment`, `variable` (AEME `MET_*` name), `month`
(integer `1:12`) and `value`.

## See also

[`extract_climate_point()`](http://limnotrack.com/metscale/reference/extract_climate_point.md),
[scenario_workflow](http://limnotrack.com/metscale/reference/scenario_workflow.md)

## Examples

``` r
if (FALSE) { # \dontrun{
clim <- climate_point_monthly_climatology("inst/extdata/rotorua_cmip6",
                                        lon = 176.2717, lat = -38.0790,
                                        years = 2005:2014)
} # }
```
