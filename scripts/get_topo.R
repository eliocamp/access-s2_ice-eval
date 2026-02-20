library(rcdo)
# https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/60s/60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc.html
url <- "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/60s/60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc?lat[0:1:1800],lon[0:1:21599],z[0:10:1800][0:1:21599],crs"

etopo_file <- here::here("data/raw/ETOPO.nc")

url |>
  cdo_copy() |>
  cdo_remapmean("r360x180") |>
  cdo_execute(etopo_file, options = c("-f nc"))

metR::ReadNetCDF(etopo_file) |>
  data.table::copy() |>
  # _[, z := Smooth2D(lon, lat, z)] |>
  ggplot(aes(lon, lat)) +
  geom_contour_fill(aes(z = z)) +
  geom_contour2(aes(z = z), breaks = 0)
