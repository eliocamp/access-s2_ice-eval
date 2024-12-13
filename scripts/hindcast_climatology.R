library(furrr)

plan(multisession, workers = 12)

source(here::here("R/datasets.R"))

times <- get_forecast_times("S2")

nsidc_grid <- here::here("data/raw/nsidc_grid.txt")

months <- 1:12

furrr::future_walk(months, \(month) {
  month <- formatC(month, width = 2, flag = "0")
  files <- here::here(glue::glue("data/derived/hindcast_ensmean/di_aice_*{month}01_emm.nc")) |> 
    Sys.glob()
  files_chr <- paste0(files, collapse = " ")
  
  out <- here::here(glue::glue("data/derived/hindcast_climatology/mo_aice_1981{month}01_mean.nc"))
  dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
  glue::glue("cdo -L -O -s ensmean [ -monmean : {files_chr} ] {out}") |> 
    system()
})


