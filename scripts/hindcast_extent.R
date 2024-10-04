library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 25))
message(workers, " workers")

plan(multisession, workers = workers)

source(here::here("R/datasets.R"))

get_forecast_times <- function(dir) {
    years <- list.files(file.path(dir, "e01")) |>
        strcapture(
            pattern = "di_a?ice_(\\d{4})\\d{4}_e01.nc",
            proto = list(time = numeric(1))
        ) |>
        range()

    seq(as.Date(paste0(years[1], "-01-01")),
        as.Date(paste0(years[2], "-01-01")),
        by = "month"
    )
}

forecast_times_s2 <- get_forecast_times("/g/data/ux62/access-s2/hindcast/raw_model/ice/aice/daily/")

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


forecast_times_s1 <- get_forecast_times("/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/")

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
