logfile <- here::here("logs/error_metrics.log")q
log <- function(text) {
  messg <- paste0(format(lubridate::now()), ": ", text)
  if (interactive()) {
    message(messg)
  } else {
    write(messg, logfile, append = TRUE)    
  }
}
on.exit(log("exiting"))
writeLines("", logfile)
log("Booting up")

library(furrr)

workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 2))
plan_type <- "multicore"
log(glue::glue("setting up {workers} workers in a {plan_type} plan"))

plan(plan_type, workers = workers)

log("Finished setting plan")

library(rcdo)
cdo_options_set("-L")
library(data.table)
library(lubridate)
library(ncdf4)
source(here::here("R/functions.R"))
source(here::here("R/datasets.R"))

# Force evaluation now and not in the workers.
obs <- list(
  data = list(
    cdr = CDR() |>
      force(),
    osi = OSI() |>
      force()
  )
)

climatologies <- obs$data |>
  future_map(climatology)

obs$anomalies <- future_map(names(climatologies), \(n) {
  anomalies(obs$data[[n]], climatologies[[n]])
}) |>
  setNames(names(climatologies))


rmse_dir <- here::here("data/derived", "rmse")
dir.create(rmse_dir, showWarnings = FALSE)

rmse_lon_dir <- here::here("data/derived", "rmse_lon")
dir.create(rmse_lon_dir, showWarnings = FALSE)

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


get_part <- function(file, first_time, last_time) {
  file_name <- paste(tools::file_path_sans_ext(basename(file)), 
                     first_time, 
                     last_time, sep = "_")
  
  outfile <- here::here("data/temp/part", file_name)
  file.create(dirname(outfile), showWarnings = FALSE, recursive = TRUE)
  if (file.exists(outfile)) {
    return(outfile)
  }
  
  file |>
    cdo_seldate(
      startdate = as.character(first_time),
      enddate = as.character(last_time)
    ) |>
    cdo_execute(options = "-L", output = outfile)
}


get_times <- function(file) {
  times <- cdo_showtimestamp(file) |> 
    cdo_execute() |> 
    strsplit(" ") |> 
    unlist() |> 
    Filter(f = nzchar) |> 
    as.POSIXct(tz = "UTC")
}

dlon <- 15

limits <- seq(-180, 180, by = dlon)

cdo_addlevel <- function(file, level) {
  zaxis <- tempfile()
  glue::glue("zaxistype = height\nsize = 1\nlevels=1\nname=lon") |> 
    writeLines(zaxis)
  
  file |> 
    cdo_setzaxis(zaxis) |> 
    cdo_setlevel(level) 
}


cdo_setlon <- function(file, lon) {
  gridfile <- tempfile()
  grid <- file |> 
    cdo_griddes() |> 
    cdo_execute()
  gsub("xvals += +0", glue::glue("xvals = {lon}"), grid) |> 
    writeLines(gridfile)
  
  cdo_setgrid(file, gridfile) 
}

regions <- list(lonmins = limits[-length(limits)],
                lonmaxs = limits[-1]) |> 
  data.table::transpose()

names(regions) <- vapply(regions, \(x) mean(c(x[[2]], x[[1]])), numeric(1))

apply_mask <- function(file, region) {
  maxlon <- region[[2]]
  minlon <- region[[1]]
  midlon <- (maxlon + minlon)/2
  
  file |> 
    cdo_expr(glue::glue("\"aice = (clon(aice) >= {minlon} && clon(aice) < {maxlon}) ? aice : missval(aice)\"")) 
}


cdo_rmse_lon <- function(file, obs, n = 15, output) {
  log(glue::glue("      computing squared difference"))
  rmse_remap <- file |> 
    cdo_sub(obs) |> 
    cdo_sqr() |>
    cdo_remapmean(glue::glue("r{n}x360")) |>
    cdo_mermean() |>
    cdo_sqrt() |>
    cdo_execute(output = output) 
}

compute_metrics <- function(forecast_time, member, version, obs_dataset) {
  tick <- lubridate::now()
  cdo_options_set(c("-L"))
  
  file <- hindcast(forecast_time, model = version, members = member)
  model_climatology <- here::here("data/derived/climatology", version, pad_number(month(forecast_time)), "em.nc")
  
  file_template <- paste0("di_aice_", format(forecast_time, "%Y%m%d"), "_e0", member, ".nc")
  
  rmse_out <- file.path(rmse_dir, version, obs_dataset, file_template)
  dir.create(dirname(rmse_out), showWarnings = FALSE, recursive = TRUE)
  
  rmse_lon_out <- file.path(rmse_lon_dir, version, obs_dataset, file_template)
  dir.create(dirname(rmse_lon_out), showWarnings = FALSE, recursive = TRUE)
  
  rmse_lon_persistence_out <- file.path(rmse_lon_dir, "persistence", obs_dataset, paste0("di_aice_", format(forecast_time, "%Y%m%d"), "_e01.nc"))
  dir.create(dirname(rmse_lon_persistence_out), showWarnings = FALSE, recursive = TRUE)
  
  iiee_out <- file.path(iiee_dir, version, obs_dataset, file_template)
  dir.create(dirname(iiee_out), showWarnings = FALSE, recursive = TRUE)
  
  rmse_out_persistence <- file.path(rmse_dir, "persistence", obs_dataset, paste0("di_aice_", format(forecast_time, "%Y%m%d"), "_e01.nc"))
  dir.create(dirname(rmse_out_persistence), showWarnings = FALSE, recursive = TRUE)
  
  if (all(file.exists(c(rmse_out_persistence, rmse_out, iiee_out, rmse_lon_out, rmse_lon_persistence_out)))) {
    return()
  }
  
  log(glue::glue("Computing {forecast_time} - {version} {member} with {obs_dataset}"))
  
  log(glue::glue("opening {basename(file)}"))
  
  times <- get_times(file)
  
  last_time <- max(times)
  first_time <- min(times)
  
  log(glue::glue("getting part {basename(file)}"))
  observation_part <- get_part(obs$data[[obs_dataset]], first_time, last_time)
  
  observation_part_anomaly <- get_part(obs$anomalies[[obs_dataset]], first_time, last_time)
  
  times_obs <- get_times(observation_part)
  
  if (!file.exists(rmse_out)) {
    file |>
      cdo_ydaysub(model_climatology) |>
      cdo_rmse(observation_part_anomaly) |>
      cdo_execute(output = rmse_out)
  }
  
  if (!file.exists(rmse_lon_out)) {
    log(glue::glue("   computing rmse_lon {basename(file)}"))
    
    file |> 
      cdo_ydaysub(model_climatology) |> 
      cdo_rmse_lon(observation_part_anomaly, 
                   output = rmse_lon_out)
  }
  
  if (!file.exists(iiee_out)) {
    cdo_iiee(file, observation_part, output = iiee_out)
  }
  
  if (!file.exists(rmse_out_persistence)) {
    persistence <- cdo_persist(obs$anomalies[[obs_dataset]],
                               observation_part_anomaly,
                               init_time = as.character(forecast_time)
    )
    
    times_persistence <- get_times(persistence)
    
    if (length(times_persistence) != length(times_obs)) {
      stop("malos tiempos en la persistencia de ", i)
    }
    
    rmse_persistence <- cdo_rmse(persistence, observation_part_anomaly) |>
      cdo_execute(output = rmse_out_persistence)
  }
  
  if (!file.exists(rmse_lon_persistence_out)) {
    log("   computing rmse_lon persistence")
    if (!exists("persistence")) {
      log("   persisting")
      persistence <- cdo_persist(obs$anomalies[[obs_dataset]],
                                 observation_part_anomaly,
                                 init_time = as.character(forecast_time))
    }
    
    log("   rmse_lon")
    
    persistence |> 
      cdo_rmse_lon(observation_part_anomaly, 
                   output = rmse_lon_persistence_out)
  }
  
  tock <- lubridate::now()
  log(glue::glue("   done in {as.numeric(tock) - as.numeric(tick)} seconds"))
}


forecast_times_s1 <- get_forecast_times("S1") |> 
  Filter(f = \(x) mday(x) == 1) 

forecast_times_s2 <- get_forecast_times("S2") |> 
  Filter(f = \(x) mday(x) == 1) 

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
  _[mday(forecast_time) == 1]

i <- 2

forecast_time <- all_files[i, ]$forecast_time
obs_dataset  <-  all_files[i, ]$obs_dataset
version  <-  all_files[i, ]$version
member  <-  all_files[i, ]$member

future_pwalk(all_files, compute_metrics, .options = furrr_options(seed = NULL))


read_measures <- function(dir) {
  files <- list.files(dir, include.dirs = FALSE, recursive = TRUE, full.names = TRUE) 
  
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
    data <- try(metR::ReadNetCDF(ncfile, vars = c(value = "aice")), silent = TRUE)
    
    if (inherits(data, "try-error")) {
      file.remove(files[[i]])
      warning("file ", basename(files[[i]]), " deleted")
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

