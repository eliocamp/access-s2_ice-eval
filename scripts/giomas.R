
years <- 1981:2018

download_giomas <- function(year) {
  library(data.table)
  gzip <- function(file) {
    system(glue::glue("gzip -d {file}"))
    gsub(".gz", "", file)
  }

  sh_subset <- list(j = 1:71)  # points in the southern hemisphere
  
  url <- glue::glue("http://pscfiles.apl.uw.edu/zhang/Global_seaice/heff.H{year}.nc.gz")
  options(download.file.method="curl", download.file.extra="-k -L")
  
  thickness <- tempfile(fileext = ".nc.gz")
  download.file(url, thickness)
  thickness <- gzip(thickness) |> 
    rcdo::cdo_settaxis(glue::glue("{year}-01-01,00:00:00,1mon")) |> 
    rcdo::cdo_execute()
  

  url <- glue::glue("http://pscfiles.apl.uw.edu/zhang/Global_seaice/area.H{year}.nc.gz")
  concentration <- tempfile(fileext = ".nc.gz")
  download.file(url, concentration)
  
  concentration <- gzip(concentration) |> 
    rcdo::cdo_settaxis(glue::glue("{year}-01-01,00:00:00,1mon")) |> 
    rcdo::cdo_execute()

  list(thickness = thickness, 
      concentration = concentration,
      year = year)
}

library(mirai)
daemons(6)

data <- mirai_map(years, download_giomas)[.progress] |> 
  data.table::rbindlist() 


data$thickness[1] |> 
  rcdo::cdo_selname("lon_scaler,lat_scaler,dxt,dyt") |> 
  rcdo::cdo_execute("data/raw/giomas_grid.nc", options = "-L")


data$thickness |> 
  lapply(\(x) rcdo::cdo_selname(x, "heff")) |> 
  rcdo::cdo_mergetime() |> 
  rcdo::cdo_execute("data/raw/giomas_thickness.nc", options = c("-L -O"))


data$concentration |> 
  lapply(\(x) rcdo::cdo_selname(x, "area")) |> 
  rcdo::cdo_mergetime() |> 
  rcdo::cdo_execute("data/raw/giomas_concentration.nc", options = c("-L -O"))
  