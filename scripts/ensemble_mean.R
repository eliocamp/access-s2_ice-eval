library(rcdo)
library(data.table)
library(metR)
source(here::here("R/datasets.R"))

future::plan("multicore", workers = 40)

file <- get_forecast_times("S2") |> 
  Filter(f = \(x) lubridate::day(x) == 1 & lubridate::month(x) == 1) |> 
  _[2] |> 
  hindcast(model = "S2", members = 1)

ndays <- as.numeric(cdo_ntime(file) |> 
                      cdo_execute())

bytes_per_day <- file.size(file)/ndays

compute_ensemble_mean <- function(forecast_time, model, variable) {
  month <- data.table::month(forecast_time)
  # the 7th member has some weird jumps and inconsistencies. 
  if (model == "S1" && month == 1) {
    members <- c(1:6, 8:9)
  } else {
    members <- 1:9
  }
  
  files <- hindcast(forecast_time, model, members, variable)
  
  # Some forecast have less than the correct number of days. 
  # Throw them out
  size <- files |> 
    file.size()
  
  ndays <- floor(size/bytes_per_day)
  
  out <- here::here("data/derived/hindcast", variable, model, forecast_time, "em.nc")
  
  files[ndays >= 215] |> 
    cdo_ensmean() |> 
    cdo_execute(out, options = "-L -O", cache = TRUE)
}


S2_times <- get_forecast_times("S2") |> 
  Filter(f = \(x) mday(x) == 1) |> 
  _[-1]


S1_times <- get_forecast_times("S1") |> 
  Filter(f = \(x) mday(x) == 1) 

furrr::future_map(S2_times, compute_ensemble_mean, model = "S2", variable = "hi")
furrr::future_map(S1_times, compute_ensemble_mean, model = "S1", variable = "hi")

furrr::future_map(S2_times, compute_ensemble_mean, model = "S2", variable = "aice")
furrr::future_map(S1_times, compute_ensemble_mean, model = "S1", variable = "aice")


