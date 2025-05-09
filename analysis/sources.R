library(ggplot2)

og_extent <- BT() |>
    rcdo::cdo_gtc(0.15) |>
    rcdo::cdo_fldint() |>
    rcdo::cdo_execute(options = c("-L"))

cdr_extent <- CDR_BT() |>
    rcdo::cdo_gtc(0.15) |>
    rcdo::cdo_fldint() |>
    rcdo::cdo_execute(options = c("-L"))

# era5_extent <- ERA5() |>
#     rcdo::cdo_gtc(0.15) |>
#     rcdo::cdo_fldint() |>
#     rcdo::cdo_execute(options = c("-L"))


extents <- metR::ReadNetCDF(og_extent,
    vars = c(og_bt = "aice")
) |>
    _[
        metR::ReadNetCDF(cdr_extent,
            vars = c(cdr_bt = "aice")
        ),
        on = .NATURAL
    ] |>
    # _[
    #     metR::ReadNetCDF(era5_extent,
    #         vars = c(era5 = "aice")
    #     ) |>
    #         data.table::setnames("valid_time", "time"),
    #     on = .NATURAL
    # ] |>
    _[, lon := NULL] |>
    _[, lat := NULL]

extents |>
    data.table::copy() |>
    _[, dif := og_bt - cdr_bt] |>
    data.table::melt(id.vars = "time", value.name = "extent") |>
    _[extent == 0, extent := NA] |>
    # _[, value := value - mean(value, na.rm = TRUE), by = .(data.table::yday(time))] |>
    _[data.table::year(time) == 2023] |>
    ggplot(aes(time, extent)) +
    geom_line(aes(color = variable))

extents |>
    data.table::copy() |>
    _[, dif := og_bt - cdr_bt] |>
    data.table::melt(id.vars = "time", value.name = "extent") |>
    _[extent == 0, extent := NA] |>
    # _[, value := value - mean(value, na.rm = TRUE), by = .(data.table::yday(time))] |>
    _[data.table::year(time) == 2000] |>
    ggplot(aes(time, extent)) +
    geom_line(aes(color = variable))


extents |>
    data.table::copy() |>
    _[, dif := og_bt - cdr_bt] |>
    data.table::melt(id.vars = "time", value.name = "extent") |>
    _[extent == 0, extent := NA] |>
    _[, .(extent = mean(extent, na.rm = TRUE)), by = .(variable, yday = data.table::yday(time))] |>
    # _[data.table::year(time) == 2000] |>
    ggplot(aes(yday, extent)) +
    geom_line(aes(color = variable))

extents |>
    data.table::copy() |>
    _[, dif := og_bt - cdr_bt] |>
    data.table::melt(id.vars = "time", value.name = "extent") |>
    _[extent == 0, extent := NA] |>
    _[, .(extent = mean(extent, na.rm = TRUE)), by = .(variable, yday = data.table::yday(time))] |>
    _[variable == "dif"] |>
    # _[data.table::year(time) == 2000] |>
    ggplot(aes(yday, extent)) +
    geom_line(aes(color = variable))




e <- extents |>
    data.table::melt(id.vars = "time") |>
    _[value == 0, value := NA] 

e |>
    data.table::copy() |>
    data.table::setnames(c("variable", "value"), c("variable2", "value2")) |>
    _[] |>
    _[e, on = "time", allow.cartesian = TRUE] |>
    _[, sqrt(mean((value2 - value)^2, na.rm = TRUE))/1e12,
        by = .(variable, variable2, yday = data.table::yday(time))]  |>
    _[variable != variable2] |>
    _[variable != "era5"] |>
    unique() |>
    ggplot(aes(yday, V1)) +
    geom_line(aes(color = variable2)) +
    facet_wrap(~ variable)


abs_dif <- rcdo::cdo_sub(BT(), CDR_BT()) |>
    rcdo::cdo_abs() |>
    rcdo::cdo_timmean() |>
    rcdo::cdo_execute(options = c("-L"))




(g <- metR::ReadNetCDF(abs_dif, vars = c(dif = "aice")) |>
    ggplot(aes(xgrid, ygrid)) +
    # metR::geom_contour_fill(aes(z = N07_ICECON)) +
    geom_raster(aes(fill = dif)) +
    scale_fill_viridis_c(NULL) +
    coord_equal() +
    scale_x_continuous(NULL, expand = c(0, 0), breaks = NULL) +
    scale_y_continuous(NULL, expand = c(0, 0), breaks = NULL) +
    theme_minimal() +
    labs(title = "Mean absolute difference between Bootstrap from polarwatch/CDR and from NSIDC"))


g +
    coord_equal(
        xlim = c(-3e6, -1e6),
        ylim = c(0, 2e6)
    )
