logfile <- here::here(glue::glue("logs/error_metrics_read.log"))
log <- function(text) {
  messg <- paste0(format(lubridate::now()), ": ", text)
  if (interactive()) {
    message(messg)
  } else {
    write(messg, logfile, append = TRUE)
  }
}
writeLines("", logfile)
log("Booting up")

library(furrr)

workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 2))
plan_type <- "multicore"
log(glue::glue("setting up {workers} workers in a {plan_type} plan"))

plan(plan_type, workers = workers)


rmse_dir <- here::here("data/derived", "rmse")

rmse_lon_dir <- here::here("data/derived", "rmse_lon")

iiee_dir <- here::here("data/derived", "iiee")


read_measures <- function(dir) {
  files <- list.files(
    dir,
    include.dirs = FALSE,
    recursive = TRUE,
    full.names = TRUE
  )

  dates <- paste0(
    here::here("data/derived"),
    "/(\\w*)/(\\w*)/(\\w*)/di_aice_(\\d{8})_e(\\d{2}|0em).nc"
  ) |>
    utils::strcapture(
      files,
      proto = list(
        measure = character(),
        version = character(),
        obs_dataset = character(),
        time_forecast = character(),
        member = character()
      ),
      perl = TRUE
    ) |>
    data.table::as.data.table() |>
    _[, time_forecast := as.Date(time_forecast, format = "%Y%m%d")] |>
    _[]

  # rmse_lon is 360 times larger than the other measures, so it
  # just doesnt fit into memory. :(
  # if (dates$measure[1] == "rmse_lon") {
  #   which_read <- dates[, which(obs_dataset == "cdr")]
  #   files <- files[which_read]
  #   dates <- dates[which_read]
  # }

  future_map(seq_along(files), \(i) {
    ncfile <- ncdf4::nc_open(files[[i]])
    on.exit(ncdf4::nc_close(ncfile))
    data <- try(
      metR::ReadNetCDF(ncfile, vars = c(value = "aice")),
      silent = TRUE
    )

    if (inherits(data, "try-error")) {
      file.remove(files[[i]])
      log(glue::glue("file {files[[i]]} deleted"))
      return(NULL)
    }

    data |>
      _[, let(lat = NULL)] |>
      cbind(dates[i]) |>
      _[]
  }) |>
    data.table::rbindlist()
}

log("Reading RMSE")
rmse_dir |>
  read_measures() |>
  _[, lon := NULL] |>
  saveRDS(here::here("data/derived", "rmse.Rds"))

log("Reading IIEE")
iiee_dir |>
  read_measures() |>
  _[, lon := NULL] |>
  saveRDS(here::here("data/derived", "iiee.Rds"))

log("Reading RMSE_lon")
rmse_lon_dir |>
  read_measures() |>
  _[, let(measure = NULL)] |>
  saveRDS(here::here("data/derived", "rmse_lon.Rds"))

log("Finished")
0
