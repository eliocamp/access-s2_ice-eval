
lags <- c(5, 10, 15)
lags <- setNames(lags, lags)

lag <- 30
file <- anomalies(datasets$cdr)
autocor <- function(file, lag) {
  remove <- "timestep=1/{lag}/1" |> 
    glue::glue()
  
  shift <- "-{lag}day" |> 
    glue::glue()
  
  out <- file |> 
    cdo_delete(timestep = remove) |>
    cdo_timcor(file) |> 
    cdo_execute(tempfile())
  
}


corlags <- lapply(lags, \(lag) autocor(anomalies(datasets$cdr), lag))

corlags |> 
  setNames(lags) |> 
  lapply(ReadNetCDF, c("aice", "pvalue")) |> 
  rbindlist(idcol = "lag") |> 
  _[aice <= 1] |> 
  ggplot(aes(xgrid, ygrid)) +
  geom_contour_fill(aes(z = aice)) +
  # geom_point(data = \(x) x[pvalue < 0.5]) +
  scale_fill_divergent() +
  coord_equal() +
  facet_wrap(~ lag)
