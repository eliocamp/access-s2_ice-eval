library(rcdo)
source(here::here("R/datasets.R"))

future::plan("multicore", workers = 24)

dates <- get_forecast_times("S2")

dates <- dates[lubridate::day(dates) %in% 1]

dates <- lapply(dates, \(x) x - c(2, 1, 0)) |> 
  setNames(dates)

# The first time doesn't have previous days
dates <- dates[-1]


process_ice <- function(file, shift, file_out) {
  if (file.exists(file_out)) return(file_out)

  file |> 
    rcdo::cdo_selname("aice") |>
    remap_cdr() |>
    cdo_shifttime(shiftValue = paste0(shift, "day")) |> 
    cdo_del29feb() |> 
    cdo_execute(output = file_out)
}

get_file <- function(forecast_time, member) {
  paste0(
    "/g/data/ux62/access-s2/hindcast/raw_model/ice/aice/daily/e0",
    member,
    "/di_aice_",
    format(as.Date(forecast_time), "%Y%m%d"),
    "_e0",
    member,
    ".nc"
  )  
}

build_ensemble_S2 <- function(forecasts, nominal_date) {
  folder <- here::here("data/derived/hindcast/S2", nominal_date)
  dir.create(folder, showWarnings = FALSE, recursive = TRUE)
  
  data <- data.table::CJ(original_forecast_date = forecasts, original_member = 1:3) |> 
    _[, file := get_file(original_forecast_date, original_member)] |> 
    _[, member := 1:9] |> 
    _[, forecast_date := as.Date(nominal_date)] |> 
    _[, file_out := file.path(folder, paste0(formatC(member, width = 2, flag = "0"), ".nc"))] |>
    _[, process_ice(file, as.numeric(forecast_date - original_forecast_date), file_out),
      by = .(forecast_date, member, original_forecast_date, original_member)]
}


furrr::future_imap(dates, build_ensemble_S2) |> 
  data.table::rbindlist() |> 
  saveRDS(here::here("data/derived/hindcast_s2.Rds"))
