median_ci <- function(x, ci = .95) {
  quantile(na.omit(x),  probs = c(0.5 - ci/2, 0.5, 0.5 + ci/2), names = FALSE) |> 
    setNames(c("low", "mid", "high")) |> 
    as.list()
}

on_gadi <- function() {
    as.numeric(Sys.getenv("ON_GADI", unset = "0")) == 1
}

ncview <- function(file) {
    system2("ncview", args = c(file), wait = FALSE)
}

compute_climatology <- function(dataset,
                                output,
                                climatology = 1981:2011,
                                runmean_number = 11,
                                year = 2000,
                                options = c("-L")) {
    dates <- c(paste0(min(climatology), "-01-01"), paste0(max(climatology), "-12-31"))

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
    file  <- here::here("data/derived/climatology", name_from_dataset(dataset))
    dir.create(dirname(file), FALSE, TRUE)

    if (file.exists(file)) {
        return(file)
    }

    compute_climatology(dataset = dataset,
                        output = file)
    return(file)
}

name_from_dataset <- function(dataset) {
    infohash <- digest::digest(file.info(dataset)[c("size", "mtime")])
    paste0(tools::file_path_sans_ext(basename(dataset)), "_", infohash, ".nc")
}

extent <- function(dataset) {
    file  <- here::here("data/derived/extent", name_from_dataset(dataset))
    dir.create(dirname(file), FALSE, TRUE)

    if (file.exists(file)) {
        return(file)
    }

    cdo_extent(dataset) |>
        rcdo::cdo_execute(output = file, options = "-L")
}

remap_cdr <- function(file) {
    nsidc_grid <- "data/raw/nsidc_grid.txt"

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
