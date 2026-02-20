library(rcdo)
library(data.table)
library(metR)
source(here::here("R/datasets.R"))

future::plan("multicore", workers = 20)

file <- get_forecast_times("S2") |>
  Filter(f = \(x) lubridate::day(x) == 1 & lubridate::month(x) == 1) |>
  _[2] |>
  hindcast(model = "S2", members = 1)

ndays <- as.numeric(
  cdo_ntime(file) |>
    cdo_execute()
)

bytes_per_day <- file.size(file) / ndays

year_clim <- c(1990, 2012)

compute_clim <- function(model, month) {
  file <- here::here(
    "data/derived/climatology",
    model,
    pad_number(month),
    "em.nc"
  )
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)

  dates <- get_forecast_times(model) |>
    Filter(f = \(x) {
      lubridate::day(x) == 1 &
        lubridate::month(x) == month &
        lubridate::year(x) %between% year_clim
    })

  hindcast(dates, model, members = "em") |>
    cdo_mergetime() |>
    cdo_ydaymean() |>
    cdo_setyear(2000) |>
    cdo_execute(output = file, options = "-L -O", cache = TRUE)
}


dates <- data.table::CJ(model = c("S1", "S2"), month = 1:12) |>
  _[, clim := furrr::future_map2_chr(model, month, compute_clim)]
