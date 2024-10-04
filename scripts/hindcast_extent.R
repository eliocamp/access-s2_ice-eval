library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 25))
message(workers, " workers")

plan(multisession, workers = workers)

source(here::here("R/functions.R"))
source(here::here("R/datasets.R"))



forecast_times_s2 <- get_forecast_times("S2")

all_files <- data.table::CJ(
    forecast_time = forecast_times_s2,
    member = 1:9
)



furrr::future_pmap(all_files, \(forecast_time, member) {
    S2_hindcast(forecast_time, member) |>
        extent() |>
        metR::ReadNetCDF("aice") |>
        _[, `:=`(
            lat = NULL, lon = NULL,
            forecast_time = forecast_time,
            member = member
        )] |>
        _[]
}) |>
    data.table::rbindlist() |>
    saveRDS("data/derived/S2_hindcast_extent.Rds")


forecast_times_s1 <- get_forecast_times("S1")

all_files <- data.table::CJ(
    forecast_time = forecast_times_s1,
    member = 1:9
)

furrr::future_pmap(all_files, \(forecast_time, member) {
    S1_hindcast(forecast_time, member) |>
        extent() |>
        metR::ReadNetCDF("aice") |>
        _[, `:=`(
            lat = NULL, lon = NULL,
            forecast_time = forecast_time,
            member = member
        )] |>
        _[]
}) |>
    data.table::rbindlist() |>
    saveRDS("data/derived/S1_hindcast_extent.Rds")
