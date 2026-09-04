# Convert AEME `MET_*` meteorology to CF / CMIP variable names and units

Renames the AEME `MET_*` columns
([`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md))
to the short variable names used by CMIP6 / CORDEX and the CF
conventions, and converts each to its CF-canonical unit.
[`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md)
is the inverse.

## Usage

``` r
met_to_cf(
  met,
  vars = NULL,
  timestep = NULL,
  time_name = "time",
  outfile = NULL
)
```

## Arguments

- met:

  data frame with a date/time column plus `MET_*` columns, or a path to
  a `.csv` / `.rds` file holding one.

- vars:

  optional subset of `MET_*` columns to convert; default every mapped
  column present.

- timestep:

  seconds represented by one row, used only for the
  precipitation/snowfall flux conversion. `NULL` (default) infers it
  from the median spacing of the time column; pass it explicitly for an
  irregular series or a single row.

- time_name:

  name for the time column in the output. Default `"time"` (CF); pass
  `"Date"` to keep the AEME name.

- outfile:

  optional path; when given the result is written with
  `utils::write.csv(row.names = FALSE)` and returned invisibly.

## Value

the data frame with CF short-name columns in CF units. Attributes
`cf_units` and `cf_standard_names` (named by the output columns) and
`timestep_s` record the conversion.

## Details

|  |  |  |  |
|----|----|----|----|
| AEME | CF / CMIP | CF standard_name | unit |
| `MET_tmpair` | `tas` | air_temperature | K |
| `MET_tmpdew` | `tdps` | dew_point_temperature | K |
| `MET_humrel` | `hurs` | relative_humidity | % |
| `MET_prsttn` | `ps` | surface_air_pressure | Pa |
| `MET_prmslp` | `psl` | air_pressure_at_mean_sea_level | Pa |
| `MET_prvapr` | `pvap` | water_vapor_partial_pressure_in_air | Pa |
| `MET_wndspd` | `sfcWind` | wind_speed | m s-1 |
| `MET_wnddir` | `sfcWindDir` | wind_from_direction | degree |
| `MET_wnduvu` | `uas` | eastward_wind | m s-1 |
| `MET_wnduvv` | `vas` | northward_wind | m s-1 |
| `MET_radswd` | `rsds` | surface_downwelling_shortwave_flux_in_air | W m-2 |
| `MET_radlwd` | `rlds` | surface_downwelling_longwave_flux_in_air | W m-2 |
| `MET_cldcvr` | `clt` | cloud_area_fraction | % |
| `MET_pprain` | `pr` | precipitation_flux | kg m-2 s-1 |
| `MET_ppsnow` | `prsn` | snowfall_flux | kg m-2 s-1 |

Unit changes: air and dew-point temperature degC -\> K; vapour pressure
hPa -\> Pa; cloud cover fraction -\> percent; precipitation and snowfall
"mm per timestep" -\> a `kg m-2 s-1` flux (dividing by the timestep in
seconds - 1 mm of water over 1 m2 is 1 kg). Wind, radiation and the
surface/sea-level pressures are already in CF units and pass through
unchanged. Columns that are not `MET_*` (an id column, say) are carried
through untouched.

## See also

[`cf_to_met()`](http://limnotrack.com/metscale/reference/cf_to_met.md)
for the inverse,
[`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md),
[`standardise_met()`](http://limnotrack.com/metscale/reference/standardise_met.md)
and
[`guess_met_vars()`](http://limnotrack.com/metscale/reference/guess_met_vars.md)
for bringing arbitrary names *to* `MET_*`.

## Examples

``` r
met <- data.frame(
  Date = seq(as.POSIXct("2024-01-01", tz = "UTC"), by = "hour", length.out = 5),
  MET_tmpair = c(15, 15.4, 16, 16.2, 15.8),
  MET_wndspd = c(3, 4, 3.5, 5, 4.2),
  MET_pprain = c(0, 0.2, 1.1, 0, 0.4))
met_to_cf(met)
#>                  time    tas sfcWind           pr
#> 1 2024-01-01 00:00:00 288.15     3.0 0.000000e+00
#> 2 2024-01-01 01:00:00 288.55     4.0 5.555556e-05
#> 3 2024-01-01 02:00:00 289.15     3.5 3.055556e-04
#> 4 2024-01-01 03:00:00 289.35     5.0 0.000000e+00
#> 5 2024-01-01 04:00:00 288.95     4.2 1.111111e-04
```
