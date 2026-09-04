# Extract daily CMIP6 / CCAM projection meteorology for a point

Reads local daily climate-projection netCDF files - one variable per
file, as produced by the NIWA CCAM downscaling of CMIP6 - samples them
at a point, decodes the model calendar to real dates, and returns the
series in AEME `MET_*` names and units. Built for the delta-change step
of
[scenario_workflow](http://limnotrack.com/climprep/reference/scenario_workflow.md):
extract the model *historical* and *future* series with this function,
form monthly change factors, and apply them to a
[`bias_correct_daily_baseline()`](http://limnotrack.com/climprep/reference/bias_correct_daily_baseline.md).

## Usage

``` r
extract_cmip6_point(
  path,
  lon,
  lat,
  vars = c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd", "MET_humrel",
    "MET_radlwd", "MET_prsttn"),
  experiments = NULL,
  method = c("bilinear", "nearest"),
  calendar = c("auto", "365_day", "360_day", "366_day", "standard"),
  tz = "Etc/GMT-12",
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

- tz:

  time zone recorded on the result; the series is daily and carries no
  time of day. Default `"Etc/GMT-12"`.

- verbose:

  print each file as it is read.

## Value

a data frame with `Date` (class `Date`), `experiment` (character) and
one column per requested variable - stacked over experiments, wide over
variables. Attributes `lon`, `lat`, `method`, `tz`.

## Details

Files are matched by the convention `<variable>_<experiment>_*.nc` (for
example `tas_ssp245_NorESM2-MM_CCAM_daily_NZ5km_bc.nc` -\> variable
`tas`, experiment `ssp245`). Recognised variables and their AEME
targets: `tas` -\> `MET_tmpair`, `pr` -\> `MET_pprain`, `sfcWind` -\>
`MET_wndspd`, `rsds` -\> `MET_radswd`, `hurs` -\> `MET_humrel`, `rlds`
-\> `MET_radlwd`, `ps` -\> `MET_prsttn`.

Units are converted from each file's own `units` attribute: Kelvin -\>
degC, `kg m-2 s-1` -\> mm day-1, metres -\> mm. Everything else is
passed through (the CCAM `pr` files are already mm day-1). `_FillValue`
is applied by ncdf4.

## See also

[scenario_workflow](http://limnotrack.com/climprep/reference/scenario_workflow.md),
[`bias_correct_daily_baseline()`](http://limnotrack.com/climprep/reference/bias_correct_daily_baseline.md),
[`disaggregate_met_to_hourly()`](http://limnotrack.com/climprep/reference/disaggregate_met_to_hourly.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cmip <- extract_cmip6_point("inst/extdata/rotorua_cmip6",
                            lon = 176.2717, lat = -38.0790)
split(cmip, cmip$experiment) |> lapply(head, 2)
} # }
```
