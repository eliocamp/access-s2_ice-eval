source(here::here("R/functions.R"))

cdo_apply <- function(ifile, operation, ofile = NULL) {
    rcdo::cdo_operator("apply", params = c("operation"), Inf, 1) |>
        rcdo::cdo(
            input = list(ifile),
            params = list(operation = operation),
            output = ofile
        )
}

CDR_grid <- function() {
    here::here("data/raw/nsidc_grid.txt")
}

CDR <- function() {
    file <- here::here("data/raw/cdr.nc")
    years <- 1981:2023

    if (file.exists(file)) {
        return(file)
    }

    urls <- paste0(
        "https://polarwatch.noaa.gov/erddap/griddap/nsidcG02202v4sh1day.nc?cdr_seaice_conc[(",
        years,
        "-01-01T00:00:00Z):1:(",
        years,
        "-12-31T00:00:00Z)][(4350000.0):1:(-3950000.0)][(-3950000.0):1:(3950000.0)]"
    )

    files <- replicate(length(urls), tempfile())
    res <- curl::multi_download(urls, files, resume = TRUE)

    files |>
        rcdo::cdo_mergetime() |>
        cdo_chname("cdr_seaice_conc", "aice") |>
        cdo_del29feb() |>
        rcdo::cdo_setgrid(CDR_grid()) |>
        rcdo::cdo_execute(output = file, options = c("-L", "-O"))

    remove(files)
    return(file)
}

CDR_BT <- function() {
    file <- here::here("data/raw/cdr_bt.nc")
    years <- 1981:2023

    if (file.exists(file)) {
        return(file)
    }

    urls <- paste0(
        "https://polarwatch.noaa.gov/erddap/griddap/nsidcG02202v4sh1day.nc?nsidc_bt_seaice_conc[(",
        years,
        "-01-01T00:00:00Z):1:(",
        years,
        "-12-31T00:00:00Z)][(4350000.0):1:(-3950000.0)][(-3950000.0):1:(3950000.0)]"
    )

    files <- replicate(length(urls), tempfile())
    res <- curl::multi_download(urls, files, resume = TRUE)

    files |>
        rcdo::cdo_mergetime() |>
        cdo_chname("nsidc_bt_seaice_conc", "aice") |>
        cdo_del29feb() |>
        rcdo::cdo_setgrid(CDR_grid()) |>
        rcdo::cdo_execute(output = file, options = c("-L", "-O"))

    remove(files)
    return(file)
}


ERA5 <- function() {
    file_raw <- here::here("data/raw/era5_ic.nc")
    file <- here::here("data/derived/era5_ic.nc")

    if (file.exists(file)) {
        return(file)
    }

    if (!file.exists(file_raw)) {
        years <- 1981:2023

        request <- list(
            dataset_short_name = "reanalysis-era5-single-levels",
            product_type = "reanalysis",
            variable = "sea_ice_cover",
            year = years,
            month = 1:12,
            day = 1:31,
            time = "00:00",
            data_format = "netcdf",
            download_format = "unarchived",
            area = c(-20, 0, -90, 360),
            target = basename(file_raw)
        )

        ecmwfr::wf_request(request, path = dirname(file_raw))
    }

    file_raw |>
        rcdo::cdo_selname("siconc") |>
        cdo_chname("siconc", "aice") |>
        remap_cdr() |>
        cdo_del29feb() |>
        rcdo::cdo_execute(output = file, options = c("-L", "-O", "-f nc"))

    system(paste0("module load nco && ncrename -O -d valid_time,time -v valid_time,time ", file, " ", file))

    return(file)
}


BT <- function() {
    file_out <- here::here("data/raw/bootstrap.nc")
    years <- 1981:2023

    if (file.exists(file_out)) {
        return(file_out)
    }

    dates <- lapply(years, \(year) {
        seq(as.Date(paste0(year, "-01-01")), as.Date(paste0(year, "-12-31")), by = "1 day")
    }) |>
        do.call(what = c) |>
        sort()

    urls <- paste0(
        "https://n5eil01u.ecs.nsidc.org/PM/NSIDC-0079.004/",
        format(dates, "%Y.%m.%d"),
        "/NSIDC0079_SEAICE_PS_S25km_",
        format(dates, "%Y%m%d"),
        "_v4.0.nc"
    )

    dir.create(here::here("data/temp/bt"), FALSE, TRUE)
    files <- file.path(here::here("data/temp/bt"), format(dates, "%Y%m%d"))
    to_download <- !file.exists(files)

    if (any(to_download)) {
        res <- curl::multi_download(urls[to_download], files[to_download],
            cookiejar = path.expand("~/.urs_cookies"),
            cookiefile = path.expand("~/.urs_cookies"),
            followlocation = TRUE,
            netrc = TRUE,
            httpauth = 1L,
            netrc_file = path.expand("~/.netrc")
        )
        fails <- subset(res, status_code != 200)

        # Magic number. This is a low size that indicates that the file doesn't
        # have enough data.
        bad_file_size <- 20118
        bads <- (file.size(files) < bad_file_size) | (files %in% fails$destfile)
        good <- files[!bads][1]

        template <- good |>
            rcdo::cdo_setrtomiss(rmin = 0, rmax = 1) |>
            rcdo::cdo_execute(options = "-L")

        furrr::future_walk(which(bads), \(x) {
            template |>
                rcdo::cdo_setdate(as.character(dates[x])) |>
                rcdo::cdo_execute(files[x], options = "-L")
        })
    }

    years_files <- furrr::future_map_chr(years, \(year) {
        rcdo::cdo_mergetime(paste0(here::here("data/temp/bt/"), year, "*")) |>
            cdo_del29feb() |>
            rcdo::cdo_setvrange(0, 1) |>
            rcdo::cdo_execute(options = c("-L", "-O"))
    })

    rcdo::cdo_mergetime(years_files) |>
        cdo_chname("N07_ICECON", "aice") |>
        rcdo::cdo_setgrid(CDR_grid()) |>
        rcdo::cdo_execute(output = file_out, options = c("-L", "-O"))

    # union |>
    #     rcdo::cdo_timfillmiss(method = "method=linear,limit=2") |>
    #     # rcdo::cdo_remapbil(CDR_grid()) |>
    #     rcdo::cdo_execute(output = file_out, options = c("-L", "-O"))

    file.remove(years_files)

    return(file_out)
}

S2_reanalysis <- function() {
    file <- here::here("data/derived/access-s2_reanalylsis.nc")

    if (file.exists(file)) {
        return(file)
    }

    years <- 1981:2023
    grid <- CDR_grid()

    weights <- rcdo::cdo_genbil("/g/data/ux62/access-s2/reanalysis/ice/aice/di_aice_1981.nc", grid) |>
        rcdo::cdo_execute(options = "-L")

    out <-  furrr::future_map_chr(years, \(year) {
        file <- file.path("data", "temp", paste0("s2-reanalys_", year, ".nc"))
        if (file.exists(file)) {
            return(file)
        }
        paste0("/g/data/ux62/access-s2/reanalysis/ice/aice/di_aice_", year, ".nc") |>
            rcdo::cdo_remap(grid = grid, weights = weights) |>
            cdo_del29feb() |>
            rcdo::cdo_execute(output = file, options = "-L")
    })

    out |>
        rcdo::cdo_mergetime() |>
        rcdo::cdo_execute(output = file, options = "-L")
}

S2_hindcast <- function(forecast_times, members = 1:9) {
    data <- data.table::CJ(forecast_time = forecast_times, member = members)

    raw_files <- paste0(
        "/g/data/ux62/access-s2/hindcast/raw_model/ice/aice/daily/e0",
        data$member,
        "/di_aice_",
        format(as.Date(data$forecast_time), "%Y%m%d"),
        "_e0",
        data$member,
        ".nc"
    )

    # exists <- file.exists(raw_files)
    # stopifnot(all(exists))

    files <- here::here("data/derived/hindcast/S2", basename(raw_files))
    dir.create(dirname(files[1]), showWarnings = FALSE, recursive = TRUE)
    vapply(seq_along(files), \(f) {
        if (file.exists(files[f])) {
            return(files[f])
        }
        raw_files[f] |>
            rcdo::cdo_selname("aice") |>
            remap_cdr() |>
            cdo_del29feb() |>
            rcdo::cdo_execute(output = files[f], options = "-L")
    }, character(1))
    files
}


S1_hindcast <- function(forecast_times, members = 1:9) {
    data <- data.table::CJ(forecast_time = forecast_times, member = members)

    raw_files <- paste0(
        "/g/data/ub7/access-s1/hc/raw_model/unchecked/ice/ice/daily/e0",
        data$member,
        "/di_ice_",
        format(as.Date(data$forecast_time), "%Y%m%d"),
        "_e0",
        data$member,
        ".nc"
    )

    exists <- file.exists(raw_files)
    stopifnot(all(exists))

    files <- here::here("data/derived/hindcast/S1", basename(raw_files))
    dir.create(dirname(files[1]), showWarnings = FALSE, recursive = TRUE)
    vapply(seq_along(files), \(f) {
        if (file.exists(files[f])) {
            return(files[f])
        }
        raw_files[f] |>
            rcdo::cdo_selname("aice") |>
            remap_cdr() |>
            cdo_del29feb() |>
            rcdo::cdo_execute(output = files[f], options = "-L")
    }, character(1))
    files
}


get_anomalies <- function(data, climatology) {
    file <- here::here("data/derived", paste0(basename(tools::file_path_sans_ext(data)), "_anomaly.nc"))
    if (file.exists(file)) {
        return(file)
    }
    cdo_ydaysub(cdo_del29feb(data), cdo_del29feb(climatology)) |>
        cdo_execute(output = file, options = "-L")
}
