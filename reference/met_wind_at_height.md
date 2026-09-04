# Adjust the wind columns of a met data frame to a new height

Applies
[`wind_at_height()`](http://limnotrack.com/climprep/reference/wind_at_height.md)
to `MET_wndspd` and, when present, the components `MET_wnduvu` /
`MET_wnduvv` (scaled by the same factor, so wind direction is
unchanged). Use it to bring a 2 m buoy record onto the 10 m convention
before
[`fit_met_bias_correction()`](http://limnotrack.com/climprep/reference/fit_met_bias_correction.md).

## Usage

``` r
met_wind_at_height(
  met,
  from,
  to = 10,
  z0 = 2e-04,
  method = c("log", "power"),
  exponent = 0.11
)
```

## Arguments

- met:

  data frame with `MET_wndspd` and/or `MET_wnduvu` + `MET_wnduvv`.

- from:

  measurement height of the wind columns, m.

- to, z0, method, exponent:

  passed to
  [`wind_at_height()`](http://limnotrack.com/climprep/reference/wind_at_height.md).

## Value

`met` with the wind columns rescaled, carrying
`attr(., "wind_height") <- to`.

## See also

[`wind_at_height()`](http://limnotrack.com/climprep/reference/wind_at_height.md),
[`prepare_obs_met()`](http://limnotrack.com/climprep/reference/prepare_obs_met.md)
(which takes a `wind_height` argument).

## Examples

``` r
d <- data.frame(Date = Sys.time() + 0:3 * 3600,
                MET_wndspd = c(2, 4, 3, 5))
met_wind_at_height(d, from = 2)
#>                  Date MET_wndspd
#> 1 2026-09-04 02:19:03   2.349485
#> 2 2026-09-04 03:19:03   4.698970
#> 3 2026-09-04 04:19:03   3.524228
#> 4 2026-09-04 05:19:03   5.873713
```
