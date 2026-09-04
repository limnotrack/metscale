# Wind speed and direction to vector components

Wind speed and direction to vector components

## Usage

``` r
ds2uv(d, s)
```

## Arguments

- d:

  direction the wind blows *from*, degrees.

- s:

  wind speed, m/s.

## Value

matrix with columns `u` (eastward) and `v` (northward), m/s.

## Examples

``` r
ds2uv(225, 5)
#>             u        v
#> [1,] 3.535534 3.535534
```
