#' Visualise sf objects
#'
#' This set of geom, stat, and coord are used to visualise sf objects.
#' Generally you will only ever need to use \code{geom_sf}: it will
#' automatically use \code{stat_sf} and \code{coord_sf} for you.
#'
#' Each layer needs to use the same CRS. \code{coord_sf} will warn if
#' they are not all equal, but you will need to fix the problem using
#' \code{\link[sf]{st_transform}}.
#'
#' @examples
#' nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"))
#' ggplot(nc) +
#'   geom_sf(aes(geometry = geometry)) +
#'   coord_sf(crs = sf::st_crs(nc))
#'
#' nc2 <- sf::st_transform(nc, "+init=epsg:3857")
#' ggplot(mapping = aes(geometry = geometry)) +
#'   geom_sf(data = nc) +
#'   geom_sf(data = nc2)
#' @name ggsf
NULL


# stat --------------------------------------------------------------------

#' @export
#' @rdname ggsf
StatSf <- ggproto("StatSf", Stat,
  compute_group = function(data, scales) {
    bbox <- sf::st_bbox(data$geometry)
    data$xmin <- bbox[["xmin"]]
    data$xmax <- bbox[["xmax"]]
    data$ymin <- bbox[["ymin"]]
    data$ymax <- bbox[["ymax"]]

    data
  },

  required_aes = c("geometry")
)

#' @export
#' @rdname ggsf
#' @inheritParams stat_identity
stat_sf <- function(mapping = NULL, data = NULL, geom = "rect",
                    position = "identity", na.rm = FALSE, show.legend = NA,
                    inherit.aes = TRUE, ...) {
  layer(
    stat = StatSf, data = data, mapping = mapping, geom = geom,
    position = position, show.legend = show.legend, inherit.aes = inherit.aes,
    params = list(na.rm = na.rm, ...)
  )
}

# geom --------------------------------------------------------------------

#' @export
#' @rdname ggsf
GeomSf <- ggproto("GeomSf", Geom,
  required_aes = "geometry",
  default_aes = aes(
    colour = "grey35",
    fill = NA,
    size = 0.5,
    linetype = 1,
    alpha = NA
  ),
  draw_key = draw_key_polygon,

  draw_panel = function(data, panel_scales, coord) {
    if (!inherits(coord, "CoordSf")) {
      stop("geom_sf() must be used with coord_sf()", call. = FALSE)
    }

    coord <- coord$transform(data, panel_scales)

    gpars <- lapply(1:nrow(data), function(i) sf_gpar(coord[i, , drop = FALSE]))
    grobs <- Map(sf::st_as_grob, coord$geometry, gp = gpars)
    do.call("gList", grobs)
  }
)

sf_gpar <- function(row) {
  gpar(
    col = row$colour,
    fill = alpha(row$fill, row$alpha),
    lwd = row$size * .pt,
    lty = row$linetype,
    lineend = "butt"
  )
}

#' @export
#' @rdname ggsf
#' @inheritParams geom_point
geom_sf <- function(mapping = NULL, data = NULL, stat = "sf",
                    position = "identity", na.rm = FALSE, show.legend = NA,
                    inherit.aes = TRUE, ...) {
  c(
    layer(
      geom = GeomSf, mapping = mapping,  data = data, stat = stat,
      position = position, show.legend = show.legend, inherit.aes = inherit.aes,
      params = list(na.rm = na.rm, ...)
    ),
    coord_sf()
  )
}

#' @export
scale_type.sfc <- function(x) "identity"


# Coord -------------------------------------------------------------------

#' @export
#' @rdname ggsf
#' @inheritParams coord_cartesian
CoordSf <- ggproto("CoordSf", CoordCartesian,
  transform = function(self, data, panel_scales) {
    crs <- sf::st_crs(data$geometry)
    if (is.null(self$crs)) {
      self$crs <- crs
    } else {
      if (!identical(crs, self$crs)) {
        warning(
          "coord_sf(): Inconsistent CRS: \n",
          "[1] ", self$crs, "\n",
          "[2] ", crs,
          call. = FALSE
        )
      }
    }

    data$geometry <- sf_rescale01(
      data$geometry,
      panel_scales$x_range,
      panel_scales$y_range
    )
    data
  },

  train = function(self, scales) {
    # Bounding box of the data
    x_range <- scales$x$dimension(c(0.05, 0))
    y_range <- scales$y$dimension(c(0.05, 0))
    bbox <- c(
      x_range[1], y_range[1],
      x_range[2], y_range[2]
    )

    # Generate graticular, using CRS specified in coord_sf()
    # (Should be able to derive with the data with some internal changes)
    graticule <- sf::st_graticule(bbox, crs = self$crs, datum = self$crs)

    # Expand ranges include the full graticule
    graticule_bbox <- sf::st_bbox(graticule)
    x_range <- graticule_bbox[c(1, 3)]
    y_range <- graticule_bbox[c(2, 4)]

    # Rescale to plotting coordinate system
    graticule$geom <- sf_rescale01(graticule$geom, x_range, y_range)
    graticule$x_start <- sf_rescale01_x(graticule$x_start, x_range)
    graticule$x_end <- sf_rescale01_x(graticule$x_end, x_range)
    graticule$y_start <- sf_rescale01_x(graticule$y_start, y_range)
    graticule$y_end <- sf_rescale01_x(graticule$y_end, y_range)
    graticule$degree_label <- lapply(graticule$degree_label, function(x) parse(text = x)[[1]])

    list(
      x_range = x_range,
      y_range = y_range,
      graticule = graticule
    )
  },

  aspect = function(self, coord_data) {
    if (!self$lat_lon)
      return(NULL)

    # Contributed by @edzer
    mid_y <- mean(coord_data$y_range)
    ratio <- cos(mid_y * pi / 180)
    diff(coord_data$y_range) / diff(coord_data$x_range) * ratio
  },

  render_bg = function(self, coord_data, theme) {
    line_gp <- gpar(
      col = theme$panel.grid.major$colour,
      lwd = theme$panel.grid.major$size,
      lty = theme$panel.grid.major$linetype
    )
    grobs <- c(
      list(element_render(theme, "panel.background")),
      lapply(coord_data$graticule$geom, sf::st_as_grob, gp = line_gp)
    )
    ggname("grill", do.call("grobTree", grobs))
  },

  render_axis_h = function(self, coord_data, theme) {
    graticule <- coord_data$graticule
    east <- graticule[graticule$type == "E", ]

    list(
      top = guide_axis(
        east$x_start,
        east$degree_label,
        position = "top",
        theme = theme
      ),
      bottom = guide_axis(
        east$x_end,
        east$degree_label,
        position = "bottom",
        theme = theme
      )
    )
  },

  render_axis_v = function(self, coord_data, theme) {
    graticule <- coord_data$graticule
    north <- graticule[graticule$type == "N", ]

    list(
      left = guide_axis(
        north$y_start,
        north$degree_label,
        position = "left",
        theme = theme
      ),
      right = guide_axis(
        north$y_end,
        north$degree_label,
        position = "right",
        theme = theme
      )
    )
  }

)

sf_rescale01 <- function(x, x_range, y_range) {
  # Shift + affine transformation to rescale to [0, 1] x [0, 1]
  # Contributed by @edzer
  (x - c(x_range[1], y_range[1])) *
    diag(1 / c(diff(x_range), diff(y_range)))
}
sf_rescale01_x <- function(x, range) {
  (x - range[1]) / diff(range)
}


#' @param lat_lon Does the data represent latitude and longitude?
#'   If \code{TRUE} the aspect ratio will be set so that in the center
#'   of the map, 1 km easting equals 1 km northing.
#' @export
#' @rdname ggsf
coord_sf <- function(xlim = NULL, ylim = NULL, lat_lon = TRUE, expand = TRUE,
                     crs = NULL) {
  ggproto(NULL, CoordSf,
    limits = list(x = xlim, y = ylim),
    lat_lon = lat_lon,
    crs = crs,
    expand = expand
  )
}