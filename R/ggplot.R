ggplot2::theme_set(ggplot2::theme_minimal() +
            ggplot2::theme(panel.background = ggplot2::element_rect(fill = "#fafafa", color = NA),
                  legend.position = "bottom",
                  legend.title.position = "top", 
                  legend.title = ggplot2::element_text(hjust = 0.5),
                  legend.frame = ggplot2::element_rect(color = "black", linewidth = 0.4),
                  legend.key.height = grid::unit(0.75, "lines")
            ))
wide_legend <- ggplot2::theme(legend.key.width = grid::unit(1, 'null'))


colours_models <- c(
  S2 = "black",
  S1 = "#a51d2d",
  forecast = "black",
  persistence = "#1a5fb4",
  nsidc = "#1a5fb4"
)

labels_models <- c(
  S2 = "ACCESS-S2",
  S1 = "ACCESS-S1",
  forecast = "Forecast",
  persistence = "Persistence",
  nsidc = "NSIDC CDRV4"
)

scale_color_models <- ggplot2::scale_color_manual(NULL,
                                         values = colours_models,
                                         labels = labels_models
)

scale_fill_models <- ggplot2::scale_fill_manual(NULL,
                                         values = colours_models,
                                         labels = labels_models
)

labels_extent <- function(x) {
  m <- which.max(x)
  x <- scales::label_number(scale = 1e-12)(x)
  x[m] <- paste0(x[m], "\nM km²")
  x
}

labels_month <- setNames(month.abb, 1:12)


topo <- rcdo::cdo_topo(
    grid = CDR_grid(),
    ofile = here::here("data/derived", "topo.nc")
) |>
    rcdo::cdo_execute(options = c("-f nc")) |>
    metR::ReadNetCDF(c(z = "topo")) |>
    _[, .(x = xgrid, y = ygrid, z)]

get <- `$`

sic_projection <- CDR() |>
    rcdo::cdo_seltimestep(1) |>
    rcdo::cdo_execute() |>
    ncdf4::nc_open() |>
    ncdf4::ncatt_get(varid = "crs") |>
    get("proj_params")


contour <- ggplot2::StatContour$compute_group(topo, breaks = 0)
geom_antarctica_path <- ggplot2::geom_path(data = contour, ggplot2::aes(x, y, group = group), inherit.aes = FALSE, colour = "black")

geom_antarctica_fill <- ggplot2::geom_polygon(data = contour, ggplot2::aes(x, y, group = group), inherit.aes = FALSE, colour = "black", fill = "#FAFAFA")

geomcoord_antarctica <- list(
    NULL,
    ggplot2::coord_sf(crs = sic_projection, lims_method = "box"),
    ggplot2::scale_x_continuous(name = NULL, expand = c(0, 0)),
    ggplot2::scale_y_continuous(name = NULL, expand = c(0, 0)),
    geom_antarctica_path
)

scale_color_models <- ggplot2::scale_color_manual(NULL,
    values = c(
        access = "black",
        hadisst = "#3584e4",
        nsidc = "#e66100"
    ),
    labels = c(
        access = "ACCESS-S2",
        hadisst = "HadISST",
        nsidc = "NSIDC CDRV4"
    )
)