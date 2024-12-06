library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 2))
message(workers, " workers")

plan(multicore, workers = workers)

source(here::here("R/functions.R"))
source(here::here("R/datasets.R"))

run <- function(model, measure) {
  message(glue::glue("computing {measure} for {model}"))
  forecast_times <- get_forecast_times(model)
  
  all_files <- data.table::CJ(
    forecast_time = forecast_times,
    member = 1:9
  )
  
  hindcast_fun <- match.fun(glue::glue("{model}_hindcast"))
  
  fun_apply <- match.fun(measure)
  
  file <- here::here(glue::glue("data/derived/{model}_hindcast_{measure}.Rds"))
  if (file.exists(file)) {
    return(file)
  }
  
  furrr::future_pmap(all_files, \(forecast_time, member) {
    hindcast_fun(forecast_time, member) |>
      fun_apply() |> 
      metR::ReadNetCDF("aice") |>
      _[, let(lat = NULL, lon = NULL,
              forecast_time = forecast_time,
              member = member)] |>
      _[]
  }) |>
    data.table::rbindlist() |>
    saveRDS(file)
  
  return(file)
}



models <- c("S2", "S1")
measures <- c("extent", "area")

data.table::CJ(model = models, measure = measures) |> 
  purrr::pmap(run)

