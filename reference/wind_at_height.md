# Adjust wind speed from one measurement height to another

Buoy and shore anemometers commonly sit 2–3 m above the surface, whereas
reanalyses (ERA5, ERA5-Land) and the lake-model convention report wind
at **10 m**. This rescales a wind-speed series to a different height,
assuming a neutrally-stratified surface layer.

## Usage

``` r
wind_at_height(
  u,
  from,
  to = 10,
  z0 = 2e-04,
  method = c("log", "power"),
  exponent = 0.11
)
```

## Arguments

- u:

  wind speed at height `from`, m/s (vector).

- from:

  measurement height of `u`, m.

- to:

  target height, m (default 10).

- z0:

  roughness length in m for `method = "log"` (default `2e-4`), or the
  string `"charnock"` for a wind-speed-dependent open-water roughness.

- method:

  `"log"` (default) or `"power"`.

- exponent:

  power-law exponent for `method = "power"` (default 0.11).

## Value

wind speed at height `to`, m/s, same length as `u`.

## Details

- `method = "log"`:

  (default) the logarithmic wind profile,
  `u(z) = (u* / kappa) log(z / z0)`, so
  `u(to) = u(from) * log(to / z0) / log(from / z0)`. `z0` is the
  aerodynamic roughness length; the default `2e-4` m is a typical
  open-water value. `z0 = "charnock"` instead solves the Charnock
  relation `z0 = a u*^2 / g` (with `a = 0.013`) iteratively, so the
  adjustment grows with wind speed as a real sea/lake surface roughens.

- `method = "power"`:

  the power law `u(to) = u(from) (to/from)^p` with `p = exponent`
  (default `0.11`, the open-water value; use about `1/7` over land).

For 2 m -\> 10 m over water all three give a factor of roughly
1.15–1.20. The neutral-stability assumption is good for the
moderate-to-strong winds that matter for lake mixing; it over-corrects a
little in very light, stable conditions.

## See also

[`met_wind_at_height()`](http://limnotrack.com/metscale/reference/met_wind_at_height.md)
to apply this to a `MET_*` data frame.

## Examples

``` r
wind_at_height(5, from = 2)              # 2 m -> 10 m, ~5.9 m/s
#> [1] 5.873713
wind_at_height(c(2, 6, 12), from = 3, to = 10)
#> [1]  2.250415  6.751246 13.502492
wind_at_height(10, from = 2, z0 = "charnock")
#> [1] 11.8164
```
