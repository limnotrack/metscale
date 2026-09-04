# Extract hourly ERA5-Land meteorology for a point or lake

Reads monthly hourly ERA5-Land netCDF files from `path`, pulls a time
series for a location, de-accumulates the flux variables, converts
everything to standard lake-model units
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
  file_template = "nz_era5-land_%d_%02d_%s_daily.nc",
  area_crs = 2193,
  outfile = NULL,
  fill_gaps = TRUE,
  verbose = TRUE
)
```

## Arguments

- path:

  directory holding the ERA5-Land netCDF files.

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

- file_template:

  [`sprintf()`](https://rdrr.io/r/base/sprintf.html) template for the
  file names, taking the year (integer), month (integer) and ERA5
  variable name in that order. Default
  `"nz_era5-land_%d_%02d_%s_daily.nc"`.

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

Files are located with `file_template`, which defaults to the naming the
LERNZmp download scripts produce,
`nz_era5-land_<YYYY>_<MM>_<variable>_daily.nc` - note the data are
hourly despite the `_daily` suffix.

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
  path = "download_era5-land/era5_netcdf",
  lon  = 176.2717, lat = -38.0790, years = 2023:2024)

## by lake polygon, area-weighted over every overlapping grid cell
lakes <- readRDS("gis/lake_shapefile/lernzmp_lakes_master.rds")$updated
poly  <- lakes[lakes$name_final == "Rotorua", ]
met   <- extract_era5_hourly_met(
  path = "download_era5-land/era5_netcdf", geom = poly,
  method = "area", years = 2023:2024,
  outfile = "rotorua_era5_hourly_met.csv")
} # }
```
