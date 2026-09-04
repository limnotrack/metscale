# Wind vector components to speed and direction

Wind vector components to speed and direction

## Usage

``` r
uv2ds(u, v)
```

## Arguments

- u, v:

  eastward / northward wind components, m/s.

## Value

matrix with columns `dir` (degrees the wind blows *from*) and `speed`
(m/s).

## Examples

``` r
uv2ds(3, 4)
#>           dir speed
#> [1,] 216.8699     5
```
