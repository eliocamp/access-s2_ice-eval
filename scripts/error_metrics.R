library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 25))
message(workers, " workers")

plan(multisession, workers = workers)

library(rcdo)
cdo_options_set("-L")
library(data.table)
library(lubridate)

source("R/functions.R")
source("R/datasets.R")

# Force evaluation now and not in the workers.
obs <- list(
    data = list(
        cdr = CDR() |>
            force(),
        bootstrap = BT() |>
            force(),
        era5 = ERA5() |>
            force()
    )
)

climatologies <- list(
    cdr = CDR(),
    bootstrap = BT(),
    era5 = ERA5()
) |>
    furrr::future_map(climatology)

obs$anomalies <- furrr::future_map(names(climatologies), \(n) {
    get_anomalies(obs$data[[n]], climatologies[[n]])
}) |>
    setNames(names(climatologies))

# dup_clim <- function(data) {
#     cdo_mergetime(list(cdo_setyear(data, 2001), cdo_setyear(data, 2002))) |>
#         cdo_execute(options = "-L")
# }

# climatology_twice <-  cdo_mergetime(list(cdo_setyear(nsidc_climatology, 2001), cdo_setyear(nsidc_climatology, 2002))) |>
#     cdo_del29feb() |>
#     cdo_execute(options = "-L")



rmse_dir <- here::here("data/derived", "rmse")
dir.create(rmse_dir, showWarnings = FALSE)

iiee_dir <- here::here("data/derived", "iiee")
dir.create(iiee_dir, showWarnings = FALSE)

cdo_persist <- function(file, file2, init_time) {
    first_day <- cdo_seldate(file, startdate = as.character(init_time)) |>
        cdo_execute(output = tempfile(pattern = basename(file2)), options = "-L")

    out <- file2 |>
        cdo_expr(instr = "aice=1") |>
        cdo_mul(first_day) |>
        cdo_execute(output = tempfile(pattern = basename(file2)), options = "-L")

    file.remove(first_day)
    return(out)
}


get_part <- memoise::memoise(function(file, first_time, last_time) {
    outfile <- tempfile(tmpdir = "data/temp/part/")
    dir.create("data/temp/part", showWarnings = FALSE, recursive = TRUE)

    file |>
        cdo_seldate(
            startdate = as.character(first_time),
            enddate = as.character(last_time)
        ) |>
        cdo_execute(options = "-L", output = outfile)
}, cache = cachem::cache_disk("data/temp/cache"))

compute_metrics <- function(forecast_time, member, version, obs_dataset) {
    # message(i)
    cdo_options_set(c("-L"))
    # file <- files[i, ]

    if (version == "S2") {
        file <- S2_hindcast(forecast_time, member)
    } else if (version == "S1") {
        file <- S1_hindcast(forecast_time, member)
    }

    file_template <- paste0("di_aice_", format(forecast_time, "%Y%m%d"), "_e0", member, ".nc")

    rmse_out <- file.path(rmse_dir, version, obs_dataset, file_template)
    dir.create(dirname(rmse_out), showWarnings = FALSE, recursive = TRUE)

    iiee_out <- file.path(iiee_dir, version, obs_dataset, file_template)
    dir.create(dirname(iiee_out), showWarnings = FALSE, recursive = TRUE)

    rmse_out_persistence <- file.path(rmse_dir, "persistence", obs_dataset, paste0("di_aice_", format(forecast_time, "%Y%m%d"), "_e01.nc"))
    dir.create(dirname(rmse_out_persistence), showWarnings = FALSE, recursive = TRUE)

    if (all(file.exists(c(rmse_out_persistence, rmse_out, iiee_out)))) {
        return()
    }

    nc <- ncdf4::nc_open(file)
    times <- metR:::.parse_time(time = nc$dim$time$vals, units = nc$dim$time$units, calendar = nc$dim$time$calendar)
    ncdf4::nc_close(nc)

    last_time <- max(times)
    first_time <- min(times)

    observation_part <- get_part(obs$data[[obs_dataset]], first_time, last_time)

    observation_part_anomaly <- get_part(obs$anomalies[[obs_dataset]], first_time, last_time)

    nc <- ncdf4::nc_open(observation_part)
    times_obs <- metR:::.parse_time(time = nc$dim$time$vals, units = nc$dim$time$units, calendar = nc$dim$time$calendar)
    ncdf4::nc_close(nc)

    if (!file.exists(rmse_out)) {
        file |>
            cdo_ydaysub(S2 |> climatology()) |>
            cdo_rmse(observation_part_anomaly) |>
            cdo_execute(output = rmse_out)
    }

    if (!file.exists(iiee_out)) {
        cdo_iiee(file, observation_part, output = iiee_out)
    }

    if (!file.exists(rmse_out_persistence)) {
        persistence <- cdo_persist(obs$anomalies[[obs_dataset]],
            observation_part_anomaly,
            init_time = as.character(forecast_time)
        )

        nc <- ncdf4::nc_open(persistence)
        times_persistence <- metR:::.parse_time(time = nc$dim$time$vals, units = nc$dim$time$units, calendar = nc$dim$time$calendar)
        ncdf4::nc_close(nc)

        if (length(times_persistence) != length(times_obs)) {
            stop("malos tiempos en la persistencia de ", i)
        }

        rmse_persistence <- cdo_rmse(persistence, observation_part_anomaly) |>
            cdo_execute(output = rmse_out_persistence)
    }
}


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
forecast_times_s1 <- get_forecast_times("/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/")

forecast_times_s2 <- get_forecast_times("/g/data/ux62/access-s2/hindcast/raw_model/ice/aice/daily/")

all_files <- data.table::CJ(
    forecast_time = forecast_times_s1,
    member = 1:9,
    version = c("S1"),
    obs_dataset = names(obs$data)
) |>
    rbind(
        data.table::CJ(
            forecast_time = forecast_times_s2,
            member = 1:9,
            version = c("S2"),
            obs_dataset = names(obs$data)
        )
    ) |>
    as.data.frame()


furrr::future_pwalk(all_files, compute_metrics, .options = furrr::furrr_options(seed = NULL))

read_measures <- function(files) {
    dates <- paste0(here::here("data/derived"), "/(\\w*)/(\\w*)/(\\w*)/di_aice_(\\d{8})_e([\\dm]{2}).nc") |>
        utils::strcapture(files,
            proto = list(
                measure = character(),
                version = character(),
                obs_dataset = character(),
                time_forecast = character(),
                member = character()
            ), perl = TRUE
        ) |>
        as.data.table() |>
        _[, time_forecast := as.Date(time_forecast, format = "%Y%m%d")] |>
        _[]

    read <- function(i) {
        data <- try(metR::ReadNetCDF(files[[i]], vars = c(value = "aice")), silent = TRUE)

        if (inherits(data, "try-error")) {
            file.remove(files[[i]])
            warning("file ", basename(files[[i]]), " deleted")
            return(NULL)
        }

        data |>
            _[, let(lat = NULL, lon = NULL)] |>
            cbind(dates[i]) |>
            _[]
    }

    furrr::future_map(seq_along(files), read) |>
        rbindlist()
}


list.files(rmse_dir, include.dirs = FALSE, recursive = TRUE, full.names = TRUE) |>
    read_measures() |>
    saveRDS(here::here("data/derived", "rmse.Rds"))


list.files(iiee_dir, include.dirs = FALSE, recursive = TRUE, full.names = TRUE) |>
    read_measures() |>
    saveRDS(here::here("data/derived", "iiee.Rds"))
