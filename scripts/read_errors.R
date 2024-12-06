sink(here::here("logs/read_errors"))
print("hello!")
library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 7))
message(workers, " workers")

plan(multicore, workers = workers)

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
  if (dates$measure[1] == "rmse_lon") {
    which_read <- dates[, which(version == "S2" & 
                                  obs_dataset == "cdr" & member %in% c("01", "02", "03"))]
    files <- files[which_read]
    dates <- dates[which_read]
  }
  
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


rmse_dir <- here::here("data/derived", "rmse")

rmse_lon_dir <- here::here("data/derived", "rmse_lon")

iiee_dir <- here::here("data/derived", "iiee")

gc(verbose = TRUE)
print("rmse")
rmse_dir |> 
  read_measures() |>
  _[, lon := NULL] |>
  saveRDS(here::here("data/derived", "rmse.Rds"))

gc(verbose = TRUE)
print("iiee")
iiee_dir |> 
  read_measures() |>
  _[, lon := NULL] |>
  saveRDS(here::here("data/derived", "iiee.Rds"))

gc(verbose = TRUE)
print("rmse_lon")
rmse_lon_dir |> 
  read_measures() |>
  _[]
  saveRDS(here::here("data/derived", "rmse_lon.Rds"))

