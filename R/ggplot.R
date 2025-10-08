element_text_first_line <- function(...) {
  el <- ggplot2::element_text(...)
  class(el) <- union("element_text_first_line", class(el))
  el
}

# Thanks to the wizard Teun van den Brand
# https://fosstodon.org/@teunbrand/113248074175175782
element_grob.element_text_first_line <-
  function(element, label, x = NULL, y = NULL, ...) {
    twolines <- grepl("\n", label)
    y <- y - grid::unit(twolines * 0.5, "lines")
    NextMethod()
  }


ggplot2::theme_set(
  ggplot2::theme_minimal() +
    ggplot2::theme(
      panel.background = ggplot2::element_rect(fill = "#fafafa", color = NA),
      legend.position = "bottom",
      legend.title.position = "top",
      legend.title = ggplot2::element_text(hjust = 0.5),
      legend.frame = ggplot2::element_rect(color = "black", linewidth = 0.4),
      legend.key.height = grid::unit(0.75, "lines"),
      axis.text.y = element_text_first_line()
    )
)
wide_legend <- ggplot2::theme(legend.key.width = grid::unit(1, 'null'))


trans_pink <- scales::muted("#F7A8B8", l = 60, c = 100)
trans_blue <- scales::muted("#55CDFC", l = 60, c = 100)


colours_models <- c(
  S1 = "#ACA40A",
  S2 = "#9C59D1",
  cdr = "black",
  bt = "black",
  era5 = "black",
  osi = "black",
  persistence = "black",
  climatology = "gray50"
)

labels_models <- c(
  S2 = "ACCESS-S2",
  S1 = "ACCESS-S1",
  cdr = "CDR",
  bt = "Bootstrap",
  era5 = "ERA5",
  osi = "OSI",
  persistence = "Persistence",
  climatology = "Climatology"
)

scale_color_models <- ggplot2::scale_color_manual(
  NULL,
  values = colours_models,
  labels = labels_models
)

scale_fill_models <- ggplot2::scale_fill_manual(
  NULL,
  values = colours_models,
  labels = labels_models
)

labels_extent <- function(x, sep = "\n", units = "M km²") {
  m <- which.max(x)
  x <- scales::label_number(scale = 1e-12)(x)
  x[m] <- paste0(x[m], sep, units)
  x
}


labels_month <- setNames(month.abb, 1:12)


topo <- here::here("data/raw/ETOPO.nc") |>
  cdo_remapbil(CDR_grid()) |>
  cdo_execute() |>
  metR::ReadNetCDF("z") |>
  _[, .(x = xgrid, y = ygrid, z)]

get_proj <- function(x) {
  x <- ncdf4::nc_open(x)
  on.exit(ncdf4::nc_close(x))
  x |>
    ncdf4::ncatt_get(varid = "crs") |>
    _[["proj_params"]]
}

sic_projection <- CDR() |>
  get_proj()

# sic_projection <- "+proj=stere +lat_0=-90 +lat_ts=-70 +lon_0=0 +k=1 +x_0=0 +y_0=0 +a=6378273 +b=6356889.449 +units=m +no_defs"

contour_antarctica <- ggplot2::StatContour$compute_group(topo, breaks = 0)
geom_antarctica_path <- ggplot2::geom_path(
  data = contour_antarctica,
  ggplot2::aes(x, y, group = group),
  inherit.aes = FALSE,
  colour = "black"
)

geom_antarctica_fill <- ggplot2::geom_polygon(
  data = contour_antarctica,
  ggplot2::aes(x, y, group = group),
  inherit.aes = FALSE,
  colour = "black",
  fill = "#FAFAFA"
)

geomcoord_antarctica <- list(
  ggplot2::coord_equal(),
  # ggplot2::coord_sf(
  #   crs = sic_projection,
  #   lims_method = "box",
  #   label_axes = "----"
  # ),
  ggplot2::scale_x_continuous(name = NULL, expand = c(0, 0), labels = NULL),
  ggplot2::scale_y_continuous(name = NULL, expand = c(0, 0), labels = NULL)
)
