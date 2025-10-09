median_ci <- function(x, ci = .95) {
  # list(mid = mean(x, na.rm = TRUE))
  quantile(
    na.omit(x),
    probs = c(0.5 - ci / 2, 0.5, 0.5 + ci / 2),
    names = FALSE
  ) |>
    setNames(c("low", "estimate", "high")) |>
    as.list()
}

average <- function(x) {
  test <- t.test(x)
  list(
    estimate = test$estimate,
    low = test$conf.int[1],
    high = test$conf.int[2]
  )
}


on_gadi <- function() {
  as.numeric(Sys.getenv("ON_GADI", unset = "0")) == 1
}

ncview <- function(file) {
  system2("ncview", args = c(file), wait = FALSE)
}

get_forecast_times <- function(model) {
  dir <- switch(
    model,
    S1 = "/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/",
    S2 = "/g/data/ux62/access-s2/hindcast/raw_model/ice/aice/daily/",
    stop("Model needs to be S1 or S2")
  )

  dates <- list.files(file.path(dir, "e01")) |>
    strcapture(
      pattern = "di_a?ice_(\\d{8})_e01.nc",
      proto = list(date = character(1))
    ) |>
    _$date |>
    lubridate::as_date()

  dates
}

compute_climatology <- function(
  dataset,
  output,
  climatology = 1981:2011,
  runmean_number = 11,
  year = 2000,
  options = c("-L")
) {
  dates <- c(
    paste0(min(climatology), "-01-01"),
    paste0(max(climatology), "-12-31")
  )

  noisy <- dataset |>
    rcdo::cdo_seldate(
      startdate = dates[1],
      enddate = dates[2]
    ) |>
    rcdo::cdo_ydaymean() |>
    rcdo::cdo_setyear(year) |>
    rcdo::cdo_execute(options = options)

  first <- noisy |>
    rcdo::cdo_seltimestep(timesteps = paste0("1/", runmean_number, "/1")) |>
    rcdo::cdo_setyear(year + 1)

  last <- noisy |>
    rcdo::cdo_seltimestep(timesteps = paste0(-runmean_number, "/-1")) |>
    rcdo::cdo_setyear(year - 1)

  rcdo::cdo_mergetime(list(last, noisy, first)) |>
    rcdo::cdo_runmean(runmean_number) |>
    rcdo::cdo_selyear(year) |>
    rcdo::cdo_execute(output = output, options = options)
}

climatology <- function(dataset) {
  file <- here::here("data/derived/climatology", name_from_dataset(dataset))
  dir.create(dirname(file), FALSE, TRUE)

  if (file.exists(file)) {
    return(file)
  }

  compute_climatology(dataset = dataset, output = file)
  return(file)
}


anomalies <- function(dataset, climatology) {
  file <- here::here("data/derived/anomalies", name_from_dataset(dataset))
  dir.create(dirname(file), FALSE, TRUE)

  if (file.exists(file)) {
    return(file)
  }
  cdo_ydaysub(cdo_del29feb(dataset), cdo_del29feb(climatology)) |>
    cdo_execute(output = file, options = "-L")
}


name_from_dataset <- function(dataset) {
  infohash <- digest::digest(file.info(dataset)[c("size", "mtime")])
  paste0(tools::file_path_sans_ext(basename(dataset)), "_", infohash, ".nc")
}

extent <- function(dataset) {
  file <- here::here("data/derived/extent", name_from_dataset(dataset))
  dir.create(dirname(file), FALSE, TRUE)

  if (file.exists(file)) {
    return(file)
  }

  cdo_extent(dataset) |>
    rcdo::cdo_execute(output = file, options = "-L")
}

area <- function(dataset) {
  file <- here::here("data/derived/area", name_from_dataset(dataset))
  dir.create(dirname(file), FALSE, TRUE)

  if (file.exists(file)) {
    return(file)
  }
  dataset |>
    rcdo::cdo_fldint() |>
    rcdo::cdo_execute(output = file, options = "-L")
}


remap_cdr <- function(file) {
  nsidc_grid <- here::here("data/raw/nsidc_grid.txt")

  rcdo::cdo_remapbil(file, nsidc_grid)
}

cdo_chname <- function(ifile, oldname, newname, ofile = NULL) {
  rcdo::cdo_operator("chname", params = c("oldname", "newname"), 1, 1) |>
    rcdo::cdo(
      input = list(ifile),
      params = list(oldname = oldname, newname = newname),
      output = ofile
    )
}


cdo_del29feb <- function(ifile, ofile = NULL) {
  rcdo::cdo_operator("del29feb", params = NULL, 1, 1) |>
    rcdo::cdo(
      input = list(ifile),
      params = NULL,
      output = ofile
    )
}


cdo_iiee <- function(ifile1, ifile2, output, threshhold = 0.15) {
  file1 <- rcdo::cdo_gtc(ifile1, c = threshhold) |>
    rcdo::cdo_options_use("-L") |>
    rcdo::cdo_execute()

  file2 <- rcdo::cdo_gtc(ifile2, c = threshhold) |>
    rcdo::cdo_options_use("-L") |>
    rcdo::cdo_execute()

  out <- rcdo::cdo_ne(file1, file2) |>
    rcdo::cdo_fldint() |>
    rcdo::cdo_execute(output = output)

  file.remove(c(file1, file2))
  return(out)
}


cdo_rmse <- function(file1, file2) {
  rcdo::cdo_sub(file1, file2) |>
    rcdo::cdo_sqr() |>
    rcdo::cdo_fldmean() |>
    rcdo::cdo_sqrt()
}

cdo_extent <- function(file, threshhold = 0.15) {
  file |>
    rcdo::cdo_gtc(threshhold) |>
    rcdo::cdo_fldint()
}


pad_number <- function(x, pad = 2) formatC(x, width = pad, flag = "0")


sd_ci <- function(x, signif = 2, sep = "\ ", ...) {
  estimate <- sd(x, ...)

  # From https://daniellakens.blogspot.com/2019/07/calculating-confidence-intervals-around.html
  N <- sum(!is.na(x))
  alpha <- 0.05
  low_chi <- qchisq(alpha / 2, N - 1, lower.tail = TRUE)
  high_chi <- qchisq(alpha / 2, N - 1, lower.tail = FALSE)

  out <- list(
    estimate = estimate,
    p.value = NA_real_,
    low = sqrt((N - 1) / low_chi) * estimate,
    high = sqrt((N - 1) / high_chi) * estimate
  )
  out$text <- with(
    out,
    paste0(
      round(estimate, signif),
      sep,
      "(CI:\ ",
      round(low, signif),
      "\ —\ ",
      round(high, signif),
      ")"
    )
  )

  out
}


correlate <- function(x, y, signif = 2, sep = "\ ", ...) {
  correlation <- stats::cor.test(x, y, ...)
  out <- with(
    correlation,
    list(
      estimate = estimate,
      p.value = p.value,
      low = conf.int[1],
      high = conf.int[2]
    )
  )

  out$text <- with(
    out,
    paste0(
      round(estimate, signif),
      sep,
      "(CI:\ ",
      round(low, signif),
      "\ —\ ",
      round(high, signif),
      ")"
    )
  )

  out
}


rmse <- function(x, y, signif = 2, sep = "\ ", scale = 1) {
  dif <- x - y
  df <- sum(!is.na(dif)) - 2
  # rmse <- sqrt(mean(dif^2, na.rm = TRUE))
  rmse <- mean(abs(dif), na.rm = TRUE)

  p_lower <- 0.025
  p_upper <- 0.975

  out <- list(
    estimate = rmse / scale,
    p.value = NA_real_,
    low = sqrt(df / qchisq(p_upper, df = df)) * rmse / scale,
    high = sqrt(df / qchisq(p_lower, df = df)) * rmse / scale
  )

  out$text <- with(
    out,
    paste0(
      round(estimate, signif),
      sep,
      "(CI:\ ",
      round(low, signif),
      "\ --\ ",
      round(high, signif),
      ")"
    )
  )
  return(out)
}
