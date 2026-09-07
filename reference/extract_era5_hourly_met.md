# Extract hourly ERA5-Land meteorology for a point or lake

Reads monthly hourly ERA5-Land files from `path` (netCDF, or GRIB as
downloaded by
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)),
pulls a time series for a location, de-accumulates the flux variables,
converts everything to standard lake-model units
([`met_vars()`](http://limnotrack.com/metscale/reference/met_vars.md)),
shifts the time stamps from UTC to `tz` and returns a tidy wide data
frame ready to be written to CSV.

## Usage

``` r
extract_era5_hourly_met(
  path,
  lon = NULL,
  lat = NULL,
  geom = NULL,
  years = NULL,
  months = 1:12,
  variables = c("2m_temperature", "2m_dewpoint_temperature", "10m_u_component_of_wind",
    "10m_v_component_of_wind", "surface_solar_radiation_downwards",
    "surface_thermal_radiation_downwards", "total_precipitation", "snowfall",
    "surface_pressure"),
  method = c("bilinear", "nearest", "area", "area_mean"),
  tz = "Etc/GMT-12",
  format = c("AEME", "LER", "raw"),
  precip_units = c("mm/hr", "m/day", "mm/day", "m/hr"),
  pressure_units = c("Pa", "hPa"),
  pattern = "{variable}",
  max_dist_km = 50,
  area_crs = 2193,
  outfile = NULL,
  fill_gaps = TRUE,
  verbose = TRUE
)
```

## Arguments

- path:

  directory holding the ERA5-Land files (netCDF or GRIB).

- lon, lat:

  point of interest, decimal degrees (WGS84). Ignored if `geom` is
  supplied.

- geom:

  an `sf`/`sfc` point or polygon (any CRS) identifying the location;
  overrides `lon`/`lat`.

- years:

  integer vector of years to read. `NULL` (default) uses every year
  found on disk for the requested variables.

- months:

  integer vector of months to read (default `1:12`).

- variables:

  ERA5-Land variable names to read. Defaults to the nine standard
  meteorological forcing variables.

- method:

  `"nearest"`, `"bilinear"` (default), `"area"` or `"area_mean"` - see
  Details.

- tz:

  output time zone. Default `"Etc/GMT-12"` = fixed NZST (UTC+12, no
  daylight saving) which keeps a gap-free regular hourly series. Use
  `"Pacific/Auckland"` for civil NZ time (a duplicated hour every April,
  a missing hour every September).

- format:

  `"AEME"` (default, `MET_*` names), `"LER"` (LakeEnsemblR names) or
  `"raw"` (ERA5 short names).

- precip_units:

  `"mm/hr"` (default), `"m/day"`, `"mm/day"` or `"m/hr"` - applied to
  precipitation and snowfall.

- pressure_units:

  `"Pa"` (default) or `"hPa"`.

- pattern:

  file-name template matched (unanchored, case-insensitive on the
  extension) against the names in `path`. Understands the tokens
  `{variable}` - the ERA5 name such as `2m_temperature`, which also
  matches the short name (`t2m`) - `{year}` and `{month}`, plus `*` as a
  wildcard; everything else is literal. `{year}` / `{month}` are
  optional: include them to pin those fields or to select `months`; with
  no `{year}` token the first 4-digit run in the name is taken as the
  year. Only `.nc` / `.grib` / `.grb` / `.grib2` files are considered.
  Default `"{variable}"`. Examples: `"{year}_{month}_{variable}"`,
  `"*_{variable}_hourly_{year}_{month}_*"`.

- max_dist_km:

  when a `"nearest"` sample (or a `"nearest"` fallback from `"bilinear"`
  / `"area"`) is used, the distance from the requested point to the
  chosen ERA5 cell is reported, and an error is raised if it exceeds
  this many kilometres. Default `50`; `Inf` disables the check.

- area_crs:

  projected CRS (EPSG code or WKT) used to compute polygon intersection
  areas for `method = "area"`. Default `2193` (NZTM 2000); use a
  projection appropriate to your region.

- outfile:

  optional path; if given the frame is written there with
  `utils::write.csv(..., row.names = FALSE)`, time formatted
  `"%Y-%m-%d %H:%M:%S"`.

- fill_gaps:

  reindex onto a complete regular hourly sequence (missing steps become
  `NA`). Default `TRUE`.

- verbose:

  print progress messages.

## Value

a data frame: a time column (`Date` for AEME, else `datetime`; POSIXct
in `tz`) plus one column per variable in the chosen naming `format`.
Derived `*_wndspd`, `*_wnddir` and `*_humrel` columns are added when
their inputs are present. Attributes `lon`, `lat`, `method`, `tz`,
`n_cells` describe the extraction.

## Details

Files are located by matching `pattern` against the file names in
`path`. The default, `"{variable}"`, picks up any `.nc` / `.grib` file
whose name contains the ERA5 variable name (or its short name) and a
4-digit year - which covers the output of
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)
and most ad-hoc layouts. Give `pattern` explicitly to disambiguate or to
filter by `months`; see the argument description.

The reader backend is chosen per file from its extension: `.grib`,
`.grb` and `.grib2` are read with terra, anything else with ncdf4. Each
GRIB file is assumed to hold a single ERA5 variable across the month, as
[`download_era5_cds()`](http://limnotrack.com/metscale/reference/download_era5_cds.md)
writes them.

The location can be given as

- `lon` / `lat` scalars, or

- `geom` - an `sf`/`sfc` point or polygon in any CRS.

Spatial sampling (`method`):

- `"nearest"` - value of the single closest grid node to the point /
  polygon centroid.

- `"bilinear"` - bilinear interpolation between the four grid nodes
  surrounding the point / centroid.

- `"area"` - area-weighted mean of every ERA5 grid cell whose footprint
  overlaps the polygon (use when a lake straddles several cells).
  Weights are intersection areas computed in the `area_crs` projection.

- `"area_mean"`- unweighted mean of the overlapping cells. `"area"` /
  `"area_mean"` require a polygon `geom`; they fall back to `"bilinear"`
  for a point or a lake smaller than one grid cell.

Unit handling:

- 2m_temperature / 2m_dewpoint_temperature K -\> degC

- 10m_u/v_component_of_wind m s-1 -\> m s-1 (unchanged)

- surface_pressure Pa -\> Pa (or hPa)

- surface_solar_radiation_downwards (ssrd) J m-2 accum. -\> W m-2

- surface_thermal_radiation_downwards (strd) J m-2 accum. -\> W m-2

- total_precipitation (tp) m accum. -\> mm hr-1 (or m day-1)

- snowfall (sf) m accum. -\> mm hr-1 (or m day-1)

ERA5-Land accumulations run from 00:00 UTC and reset at 01:00 UTC each
day, so the hourly amount is recovered as a first difference except at
the 01:00 UTC step (and the first record), where the stored value is
already the hourly amount.

## Examples

``` r
if (FALSE) { # \dontrun{
## by coordinate
met <- extract_era5_hourly_met(
  path = "era5_land", lon = 176.2717, lat = -38.0790, years = 2023:2024)

## GRIB from download_era5_cds(), area-weighted over a lake polygon
poly <- sf::st_read("gis/rotorua.gpkg")
met  <- extract_era5_hourly_met(
  path = "era5_cds", geom = poly, method = "area", years = 2023:2024,
  pattern = "*_{variable}_hourly_{year}_{month}_*",
  outfile = "rotorua_era5_hourly_met.csv")
} # }
```
