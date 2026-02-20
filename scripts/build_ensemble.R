chunk <- as.numeric(Sys.getenv("CHUNK", 0))

library(rcdo)
source(here::here("R/datasets.R"))
cdo_cache_set()
future::plan("multicore", workers = 40)

process_ice <- function(file, shift, file_out, variable) {
  file |>
    rcdo::cdo_selname(variable) |>
    remap_cdr() |>
    cdo_shifttime(shiftValue = paste0(shift, "day")) |>
    cdo_del29feb() |>
    cdo_execute(output = file_out, cache = TRUE, options = "-L")
}


get_file <- function(forecast_time, member, model, variable = c("aice", "hi")) {
  if (model == "S2") {
    dir <- glue::glue(
      "/g/data/ux62/access-s2/hindcast/raw_model/ice/{variable}/daily/e0"
    )
    prefix <- glue::glue("/di_{variable}_")
  } else if (model == "S1") {
    dir <- "/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/e0"
    prefix <- "/di_ice_"
  }

  paste0(
    dir,
    member,
    prefix,
    format(as.Date(forecast_time), "%Y%m%d"),
    "_e0",
    member,
    ".nc"
  )
}


build_ensemble <- function(forecasts, nominal_date, model, variable) {
  folder <- here::here("data/derived/hindcast/", variable, model, nominal_date)
  dir.create(folder, showWarnings = FALSE, recursive = TRUE)

  if (model == "S2") {
    members <- 1:3
  } else {
    members <- 1:9
  }

  data <- data.table::CJ(
    original_forecast_date = forecasts,
    original_member = members
  ) |>
    _[,
      file := get_file(
        original_forecast_date,
        original_member,
        model,
        variable = variable
      )
    ] |>
    _[, member := 1:9] |>
    _[, forecast_date := as.Date(nominal_date)] |>
    _[,
      file_out := file.path(
        folder,
        paste0(formatC(member, width = 2, flag = "0"), ".nc")
      )
    ] |>
    _[,
      process_ice(
        file,
        as.numeric(forecast_date - original_forecast_date),
        file_out,
        variable
      ),
      by = .(forecast_date, member, original_forecast_date, original_member)
    ]
}

dates <- get_forecast_times("S1")

dates <- dates[lubridate::day(dates) %in% 1]
dates <- setNames(dates, dates)


if (chunk != 0) {
  n <- floor(seq(1, length(dates), length.out = 11))

  select <- seq(n[chunk], n[chunk + 1])

  dates <- dates[select]
}

furrr::future_imap(dates, build_ensemble, model = "S1", variable = "aice") |>
  data.table::rbindlist() |>
  saveRDS(here::here("data/derived/hindcast_aice_s1.Rds"))

furrr::future_imap(dates, build_ensemble, model = "S1", variable = "hi") |>
  data.table::rbindlist() |>
  saveRDS(here::here("data/derived/hindcast_hi_s1.Rds"))


dates <- get_forecast_times("S2")

dates <- dates[lubridate::day(dates) %in% 1]

dates <- lapply(dates, \(x) x - c(2, 1, 0)) |>
  setNames(dates)

# The first time doesn't have previous days
dates <- dates[-1]


if (chunk != 0) {
  n <- floor(seq(1, length(dates), length.out = 11))

  select <- seq(n[chunk], n[chunk + 1])

  dates <- dates[select]
}


furrr::future_imap(dates, build_ensemble, model = "S2", variable = "aice") |>
  data.table::rbindlist() |>
  saveRDS(here::here("data/derived/hindcast_aice_s2.Rds"))


furrr::future_imap(dates, build_ensemble, model = "S2", variable = "hi") |>
  data.table::rbindlist() |>
  saveRDS(here::here("data/derived/hindcast_hi_s2.Rds"))


0
