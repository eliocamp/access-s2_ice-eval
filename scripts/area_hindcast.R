library(data.table)
library(rcdo)
library(mirai)

cdo_options_set("-L")
cdo_cache_set(here::here("data/temp/cache"))
source(here::here("R/functions.R"))
source(here::here("R/datasets.R"))
source(here::here("R/ggplot.R"))


if (!mirai::daemons_set()) {
  invisible(daemons(parallelly::availableCores()))
}


everywhere({
  rcdo::cdo_options_set("-L")
  rcdo::cdo_cache_set(here::here("data/temp/cache"))
})


mean_weddell <- function(x, weights, sum = TRUE) {
  if (sum) {
    sum <- rcdo::cdo_fldsum
  } else {
    sum <- identity
  }
  x |>
    rcdo::cdo_remap("r360x180", weights = weights) |>
    rcdo::cdo_sellonlatbox(300, 345, -90, -30) |>
    # rcdo::cdo_setvrange(0.15, 1) |>
    sum() |>
    rcdo::cdo_execute()
}

mean_area <- function(x, lon = lon, weights) {
  weights <- rcdo::cdo_genbil(x[1], "r360x180") |>
    rcdo::cdo_execute()

  mirai::mirai_map(
    data.frame(x = x, lon = lon),
    \(x, lon) {
      out <- gsub("hindcast", paste0("hindcast_area/", lon), x)
      x |>
        rcdo::cdo_remap("r360x180", weights = weights) |>
        rcdo::cdo_sellonlatbox(lon, lon + 45, -90, -30) |>
        rcdo::cdo_fldsum() |>
        rcdo::cdo_execute(output = out)
    },
    weights = weights
  ) |>
    _[.progress] |>
    unlist()
}

hindcast <- function(forecast_time, model, member, variable = "aice") {
  here::here(
    "data/derived/hindcast",
    variable,
    model,
    forecast_time,
    paste0(formatC(member, width = 2, flag = "0"), ".nc")
  )
}

forecasts <- CJ(model = c("S1", "S2")) |>
  _[,
    .(
      forecast_time = get_forecast_times(model) |>
        Filter(f = \(x) mday(x) == 1) |>
        _[1:100]
    ),
    by = .(model)
  ] |>
  _[, .(member = 1:9), by = .(model, forecast_time)] |>
  _[, file := hindcast(forecast_time, model = model, member = member)] |>
  _[file.exists(file)]


area_forecast <- forecasts |>
  _[, .(lon = c(300, 345)), by = .(model, member, forecast_time, file)] |>
  _[, file := mean_area(file, lon, weights)]


area_std <- area |>
  _[,
    .(std = list(future::future(cdo_ensstd(file) |> cdo_execute()))),
    by = .(model, forecast_time)
  ] |>
  _[, .(std = unlist(future::value(std))), by = .(model, forecast_time)]
