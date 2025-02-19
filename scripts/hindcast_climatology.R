library(rcdo)
library(data.table)
library(metR)
source(here::here("R/datasets.R"))

future::plan("multicore", workers = 12)

file <- get_forecast_times("S2") |> 
  Filter(f = \(x) lubridate::day(x) == 1 & lubridate::month(x) == 1) |> 
  _[2] |> 
  hindcast(model = "S2", members = 1)

ndays <- as.numeric(cdo_ntime(file) |> 
             cdo_execute())

bytes_per_day <- file.size(file)/ndays

year_clim <- c(1990, 2012)

compute_clim <- function(model, month) {
  file <- here::here("data/derived/climatology", model, pad_number(month), "em.nc")
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  
  dates <- get_forecast_times(model) |> 
    Filter(f = \(x) lubridate::day(x) == 1 & lubridate::month(x) == month & lubridate::year(x) %between% year_clim) 
  
  # the 7th member has some weird jumps and inconsistencies. 
  if (model == "S1" && month == 1) {
    members <- c(1:6, 8:9)
  } else {
    members <- 1:9
  }
  forecasts <- hindcast(dates, model, 1)
  
  # Some forecast have less than the correct number of days. 
  # Throw them out
  size <- forecasts |> 
    file.size()
  
  ndays <- floor(size/bytes_per_day)
  
  forecasts[ndays >= 215] |> 
    cdo_mergetime() |> 
    cdo_ydaymean() |> 
    cdo_setyear(2000) |> 
    cdo_execute(output = file, options = "-L")
}


dates <- data.table::CJ(model = c("S1", "S2"),
                        month = 1:12) |>
  _[, clim := furrr::future_map2_chr(model, month, compute_clim)]

