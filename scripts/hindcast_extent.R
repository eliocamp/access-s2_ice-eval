library(furrr)
workers <- as.numeric(Sys.getenv("PBS_WORKERS", unset = 7))
message(workers, " workers")

plan(multicore, workers = workers)

source(here::here("R/functions.R"))
source(here::here("R/datasets.R"))

rcdo::cdo_options_set("-L")
rcdo::cdo_cache_set(here::here("data/temp/cache"))

run <- function(model, measure) {
  message(glue::glue("computing {measure} for {model}"))
  forecast_times <- get_forecast_times(model) |>
    Filter(f = \(x) data.table::mday(x) == 1)

  all_files <- data.table::CJ(
    forecast_time = forecast_times,
    member = c(1:9, "em")
  ) |>
    _[,
      file := hindcast(forecast_time, model, member),
      by = .(forecast_time, member)
    ] |>
    na.omit()

  fun_apply <- match.fun(measure)

  files <- furrr::future_pmap_chr(all_files, \(forecast_time, member, file) {
    extent <- file |>
      fun_apply()

    extent2 <- try(metR::GlanceNetCDF(extent, "aice"))

    if (inherits(extent2, "try-error")) {
      file.remove(extent)
      extent <- file |>
        fun_apply()
    }
    extent
  })

  all_files[, file := files]
}


models <- c("S2", "S1")
measures <- c("extent")

files <- data.table::CJ(model = models, measure = measures) |>
  _[order(-model)] |>
  _[, run(model, measure), by = .(model, measure)]


data <- files[,
  metR::ReadNetCDF(file, "aice"),
  by = .(model, measure, forecast_time, member)
]

data.table::fwrite(data, here::here("data/derived/hindcast_extent.csv"))
