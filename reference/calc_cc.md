# Estimate cloud cover from shortwave radiation

Inverts the ratio of measured to clear-sky potential shortwave radiation
to a cloud fraction, following Martin & McCutcheon (1999). Works at any
timestep: daily input is evaluated on an internal hourly grid (built in
`tz`) and aggregated back to daily.

## Usage

``` r
calc_cc(
  datetime,
  airt,
  swr,
  relh = NULL,
  dewt = NULL,
  lat,
  lon,
  elev = 0,
  tz = "Etc/GMT-12"
)
```

## Arguments

- datetime:

  `Date` or POSIXct timestamps matching `swr`.

- airt:

  air temperature, degC.

- swr:

  measured downwelling shortwave radiation, W m-2.

- relh:

  relative humidity, percent; used when `dewt` is absent.

- dewt:

  dew point temperature, degC.

- lat, lon:

  decimal degrees.

- elev:

  elevation, m above sea level.

- tz:

  timezone that `datetime` refers to; used to expand daily dates into
  hours. Default `"Etc/GMT-12"` (fixed NZST).

## Value

numeric vector of cloud cover fractions (0-1), same length as
`datetime`. Values that cannot be inferred (measured shortwave at or
above clear sky, or night) are linearly interpolated from neighbours.

## Examples

``` r
d <- data.frame(Date = seq(as.Date("2024-01-01"), by = "day", length.out = 10),
                airt = 18, swr = c(300, 120, 280, 90, 310, 150, 200, 260, 80, 290))
calc_cc(d$Date, airt = d$airt, swr = d$swr, relh = 70,
        lat = -38.08, lon = 176.27, elev = 280)
#>  [1] 0.6228089 1.0000000 0.6799412 1.0000000 0.5865212 0.9796327 0.8749737
#>  [8] 0.7294371 1.0000000 0.6420259
```
