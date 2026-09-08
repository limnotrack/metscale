# Build the metscale hex logo.
#
# Design: a coarse "daily" step function on the left resolves into a smooth
# sub-daily sine wave on the right (temporal disaggregation), with a line-art
# sun at the first crest and a lake line with hour ticks beneath. Palette and
# hex treatment match the sibling package limnotrack/AEME and the shared
# pkgdown theme (bg #FEF7EC, primary #0065A9).
#
# Uses only {grid} + {grDevices} (already in Imports). Run:
#   Rscript data-raw/make_logo.R

library(grid)

## palette ------------------------------------------------------------------
cream <- "#FEF7EC"
ink   <- "#111111"
blue  <- "#0065A9"

## geometry (native units: 866 x 1000, matching the hex aspect ratio) -------
cx <- 433; cy <- 500
R_out <- 486                      # fill / outer border radius
R_in  <- 466                      # inner border radius

hex_xy <- function(R) {
  ang <- c(90, 30, -30, -90, -150, 150) * pi / 180   # pointy-top
  list(x = cx + R * cos(ang), y = cy + R * sin(ang))
}

draw_logo <- function(path, width_px) {
  s <- width_px / 480
  height_px <- round(width_px / (sqrt(3) / 2))
  grDevices::png(path, width = width_px, height = height_px, units = "px",
                 bg = "transparent", type = "cairo", res = round(96 * s))
  on.exit(grDevices::dev.off())

  grid.newpage()
  pushViewport(viewport(xscale = c(0, 866), yscale = c(0, 1000)))

  nat <- function(v) unit(v, "native")

  ## hex fill + double border
  ho <- hex_xy(R_out); hi <- hex_xy(R_in)
  grid.polygon(nat(ho$x), nat(ho$y), gp = gpar(fill = cream, col = NA))
  grid.polygon(nat(ho$x), nat(ho$y), gp = gpar(col = ink, fill = NA, lwd = 4.2,
                                               linejoin = "mitre"))
  grid.polygon(nat(hi$x), nat(hi$y), gp = gpar(col = ink, fill = NA, lwd = 1.3,
                                               linejoin = "mitre"))

  ## lake line + hour ticks
  grid.lines(nat(c(116, 752)), nat(c(392, 392)),
             gp = gpar(col = ink, lwd = 4.5, lineend = "round"))
  for (tx in seq(168, 704, by = 53)) {
    grid.lines(nat(c(tx, tx)), nat(c(392, 366)),
               gp = gpar(col = ink, lwd = 3, lineend = "round"))
  }

  ## coarse daily step function (left): a rising staircase that hands off to
  ## the wave at its peak -- the same signal, coarsely then finely resolved
  sx <- c(115, 150, 150, 210, 210, 270, 270, 300)
  sy <- c(450, 450, 525, 525, 600, 600, 670, 670)
  grid.lines(nat(sx), nat(sy),
             gp = gpar(col = ink, lwd = 5, linejoin = "mitre", lineend = "butt"))

  ## smooth sub-daily wave (right), starting from the staircase peak (~1.5 cycles)
  wx <- seq(300, 748, length.out = 300)
  wy <- 555 + 115 * cos((wx - 300) / 48)
  grid.lines(nat(wx), nat(wy),
             gp = gpar(col = blue, lwd = 7.5, lineend = "round", linejoin = "round"))

  ## line-art sun above the hand-off peak
  sun_x <- 305
  sun_y <- 742
  grid.circle(nat(sun_x), nat(sun_y), r = nat(30),
              gp = gpar(col = ink, fill = NA, lwd = 3.4))
  for (a in seq(0, 2 * pi, length.out = 9)[-9]) {
    grid.lines(nat(sun_x + c(40, 54) * cos(a)), nat(sun_y + c(40, 54) * sin(a)),
               gp = gpar(col = ink, lwd = 3.4, lineend = "round"))
  }

  ## wordmark
  grid.text("metscale", x = nat(433), y = nat(212),
            gp = gpar(fontsize = 37, fontface = 2, col = ink, fontfamily = "sans"))

  invisible(path)
}

## write ------------------------------------------------------------------
fig_dir <- file.path("man", "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

draw_logo(file.path(fig_dir, "logo.png"), 480)
draw_logo(file.path(fig_dir, "logo-large.png"), 1200)

message("wrote ", file.path(fig_dir, "logo.png"), " and logo-large.png")
