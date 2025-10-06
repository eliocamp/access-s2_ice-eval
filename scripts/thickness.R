library(mirai)
library(data.table)

workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 6))
daemons(workers)

source("R/datasets.R")
source("R/functions.R")

mean_thickness <- \(model, month, year) {
  cdo_del29feb <- function(ifile, ofile = NULL) {
    rcdo::cdo_operator("del29feb", params = NULL, 1, 1) |>
      rcdo::cdo(
        input = list(ifile),
        params = NULL,
        output = ofile
      )
  }
  
  month <- formatC(month, width = 2, flag = "0")
  if (model == "S2") {
    thickness <- "/g/data/ux62/access-s2/hindcast/raw_model/ice/hi/daily/e01/di_hi_{year}{month}01_e01.nc"
  } else {
    thickness <- "/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/e01/di_ice_{year}{month}01_e01.nc"
  }
  thickness <- glue::glue(thickness)
  
  concentration <- hindcast(lubridate::make_date(year, month, 1), model = model, members = 1)
  
  if (!file.exists(thickness)) return(NA_character_)
  
  if (length(concentration) == 0) return(NA_character_)
  
  rcdo::cdo_cache_set(here::here("data/temp/cache/"))
  
  nsidc_grid <- here::here("data/raw/nsidc_grid.txt")
  
  volume <- thickness |> 
    rcdo::cdo_selname("hi") |>
    rcdo::cdo_remapbil(nsidc_grid) |> 
    rcdo::cdo_mul(concentration) |> 
    rcdo::cdo_fldint() |> 
    cdo_del29feb() 
  
  area <- concentration |> 
    rcdo::cdo_fldint() 
  out <- glue::glue("data/derived/thickness/{model}/di_ice_{year}{month}01_e01.nc")
  
  rcdo::cdo_div(volume, area) |> 
    rcdo::cdo_execute(options = "-L", output = out)
  
}


forecast_thickness <- CJ(model = c("S2", "S1"),
                         month = 1:12,
                         year = 1981:2018) |>
  _[, thickness := unlist(mirai_map(data.frame(month, year, model), mean_thickness,
                                    hindcast = hindcast, 
                                    cdo_del29feb = cdo_del29feb)[.progress])] |> 
  na.omit()

daemons(0)
