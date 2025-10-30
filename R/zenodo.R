# Hard-coded deposition ID for this project.
ZENODO_DEPOSITION_ID <- 17479538

# Internal: read the token from environment and validate
.zenodo_get_token <- function() {
  token <- Sys.getenv("ZENODO_TOKEN", unset = "")
  if (identical(token, "") || is.na(token)) {
    token <- NULL
  }
  token
}

# Internal: choose base API URL. If ZENODO_SANDBOX is set (non-empty), use the sandbox API.
.zenodo_base_url <- function(api = TRUE) {
  if (nzchar(Sys.getenv("ZENODO_SANDBOX", ""))) {
    url <- "https://sandbox.zenodo.org/"
  } else {
    url <- "https://zenodo.org"
  }

  if (api) {
    url <- paste0(url, "api")
  }

  return(url)
}

get_bucket_for_deposition <- function(deposition_id = ZENODO_DEPOSITION_ID) {
  token <- .zenodo_get_token()
  url <- paste0(.zenodo_base_url(), "/deposit/depositions/", deposition_id)

  resp <- httr2::request(url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop("Failed to fetch deposition: HTTP ", httr2::resp_status(resp))
  }

  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  if (!is.null(body$links$bucket)) {
    return(body$links$bucket)
  }

  stop("No bucket link present for deposition ", deposition_id)
}


# Ensure the given deposition is editable. If the deposition is published,
# create a new version and return the editable draft id. Otherwise return
# the deposition id (already editable).
zenodo_ensure_editable_deposition <- function(
  deposition_id = ZENODO_DEPOSITION_ID
) {
  token <- .zenodo_get_token()
  if (is.null(token)) {
    stop("ZENODO_TOKEN not set in environment; cannot access Zenodo API")
  }

  url <- paste0(.zenodo_base_url(), "/deposit/depositions/", deposition_id)
  resp <- httr2::request(url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    body <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = TRUE),
      error = function(e) NULL
    )
    msg <- if (!is.null(body) && !is.null(body$message)) {
      body$message
    } else {
      httr2::resp_status(resp)
    }
    stop("Failed to fetch deposition: ", msg)
  }

  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)

  if (isTRUE(body$submitted) || identical(body$state, "done")) {
    cli::cli_abort(
      "Deposition {deposition_id} is published. To update new files you need to create a new version and modify {.var ZENODO_DEPOSITION_ID}."
    )
  }

  # Already editable/draft
  return(as.integer(body$id))
}

# Upload a local file to the fixed deposition.
# Returns the API response for the uploaded file entry.
zenodo_upload_file <- function(path, deposition_id = ZENODO_DEPOSITION_ID) {
  if (!file.exists(path)) {
    stop("File does not exist: ", path)
  }

  zenodo_ensure_editable_deposition(deposition_id = deposition_id)

  token <- .zenodo_get_token()

  bucket <- get_bucket_for_deposition(deposition_id = deposition_id)
  filename <- basename(path) |>
    utils::URLencode(reserved = TRUE)

  cli::cli_inform("Uploading {path}")
  resp <- paste0(bucket, "/", filename) |>
    httr2::request() |>
    httr2::req_method("PUT") |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_body_file(path = path) |>
    httr2::req_timeout(60 * 60) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_progress() |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    # try to extract message if available
    body <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = TRUE),
      error = function(e) NULL
    )
    msg <- if (!is.null(body) && !is.null(body$message)) {
      body$message
    } else {
      httr2::resp_status(resp)
    }
    stop(sprintf("Failed to upload file: %s", msg))
  }

  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

zenodo_checksum_matches <- function(files) {
  checksum_local <- files |>
    vapply(\(x) digest::digest(file = x), character(1)) |>
    digest::digest()

  checksum_remote <- readLines(zenodo_download_file("checksum", tempdir()))

  return(list(
    local = checksum_local,
    remote = checksum_remote,
    matches = checksum_remote == checksum_local
  ))
}


relative_path <- function(path) {
  root <- here::here("")
  gsub(root, "", x = path)
}

zenodo_upload_data <- function(force = FALSE) {
  files <- read.csv(zenodo_files())

  files <- files[!duplicated(files$file), ]

  write.table(files, zenodo_files(), row.names = FALSE, sep = ",")

  if (nrow(files) == 0) {
    stop("No files in zenodo_files.txt")
  }

  cli::cli_inform("Checking checksum against existing checksum.")
  checksum <- zenodo_checksum_matches(files$file)

  if (!force & checksum$matches) {
    cli::cli_inform("Remote and local checksum match. Nothing to upload.")
    return(invisible(NULL))
  }

  cli::cli_inform("Creating zip file")
  zipfile <- file.path(tempdir(), "data.zip")
  zip(zipfile, files$file)

  cli::cli_inform("Uploading zip file")
  zenodo_upload_file(zipfile)

  cli::cli_inform("Uploading checksum file")
  checksum_file <- here::here("data/checksum")
  writeLines(checksum$local, checksum_file)
  zenodo_upload_file(checksum_file)
}

zenodo_is_published <- function(deposition_id = ZENODO_DEPOSITION_ID) {
  # Determine base host depending on sandbox env var
  base <- .zenodo_base_url(api = FALSE)
  # ensure no trailing slash
  base <- sub("/$", "", base)

  url <- paste0(base, "/api/records/", deposition_id)
  resp <- try(httr2::request(url) |> httr2::req_perform(), silent = TRUE)

  if (inherits(resp, "try-error")) {
    return(FALSE)
  }

  return(TRUE)
}


zenodo_download_file <- function(
  filename,
  dest = ".",
  deposition_id = ZENODO_DEPOSITION_ID
) {
  # destination directory
  if (!dir.exists(dest)) {
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  }

  is_pub <- zenodo_is_published(deposition_id = deposition_id)
  destfile <- file.path(dest, filename)

  if (is_pub) {
    cli::cli_inform(
      "Deposition {deposition_id} is published — performing public download"
    )
    base <- .zenodo_base_url(api = FALSE)
    base <- sub("/$", "", base)

    url <- paste0(
      base,
      "/records/",
      deposition_id,
      "/files/",
      utils::URLencode(filename, reserved = TRUE),
      "?download=1"
    )

    # use download.file for public download (no token)
    o <- options(timeout = 3600)
    on.exit(options(o), add = TRUE)
    utils::download.file(url, destfile, mode = "wb")
    return(invisible(destfile))
  }

  # Not published: need authenticated download
  token <- .zenodo_get_token()
  if (is.null(token)) {
    stop(
      "Deposition is not published and ZENODO_TOKEN is not set — cannot download private file"
    )
  }

  # get bucket link (uses authenticated depositions API)
  bucket <- get_bucket_for_deposition(deposition_id = deposition_id)
  file_url <- paste0(
    sub("/$", "", bucket),
    "/",
    utils::URLencode(filename, reserved = TRUE)
  )

  resp <- httr2::request(file_url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_progress() |>
    httr2::req_perform(path = destfile)

  if (httr2::resp_status(resp) >= 400) {
    body <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = TRUE),
      error = function(e) NULL
    )
    msg <- if (!is.null(body) && !is.null(body$message)) {
      body$message
    } else {
      httr2::resp_status(resp)
    }
    stop("Failed to download private file: ", msg)
  }

  return(invisible(destfile))
}


zenodo_download_data <- function(check_checksum = FALSE) {
  if (on_gadi()) {
    return(invisible(NULL))
  }

  file_list <- zenodo_files()

  if (file.exists(file_list)) {
    needed_files <- read.csv(file_list)$file |>
      Filter(f = nzchar) |>
      here::here()

    if (all(file.exists(needed_files))) {
      if (!check_checksum) {
        cli::cli_inform("All files exist, no download needed")
        return(invisible(NULL))
      }

      cli::cli_inform("Checking checksum of files")
      checksum <- zenodo_checksum_matches(needed_files)
      if (checksum$matches) {
        cli::cli_inform("Checksum matches, no download needed")
        return(invisible(NULL))
      }
    }
  }

  cli::cli_inform("Downloading data")
  dir <- here::here("data")
  data_file <- file.path(dir, "data.zip")

  if (!file.exists(data_file)) {
    data_file <- zenodo_download_file("data.zip", dir)
  } else {
    remote_checksum <- paste0(
      .zenodo_base_url(),
      "/deposit/depositions/",
      ZENODO_DEPOSITION_ID,
      "/files"
    ) |>
      httr2::request() |>
      httr2::req_perform() |>
      httr2::resp_body_json() |>
      Filter(f = \(x) x$filename == "data.zip") |>
      _[[1]] |>
      _$checksum

    local_checksum <- digest::digest(file = data_file)

    if (remote_checksum != local_checksum) {
      data_file <- zenodo_download_file("data.zip", dir)
    }
  }

  cli::cli_inform("Unzipping data")
  unzip(data_file, exdir = here::here(""))

  return(invisible(NULL))
}

on_gadi <- function() Sys.getenv("ON_GADI", unset = "null") != "null"


zenodo <- function(files, description = rep("", length(files))) {
  if (on_gadi()) {
    env <- parent.frame()
    description <- vapply(
      description,
      \(x) glue::glue(x, .envir = env),
      character(1)
    )
    data.frame(file = relative_path(files), description = description) |>
      write.table(
        file = zenodo_files(),
        append = TRUE,
        sep = ',',
        row.names = FALSE,
        col.names = FALSE
      )
  }
  return(files)
}

create_dir <- function(file_path) {
  dir.create(dirname(file_path), showWarnings = FALSE, recursive = TRUE)
  return(file_path)
}

zenodo_files <- function() {
  here::here("data/zenodo_files.csv") |>
    create_dir()
}


zenodo_init <- function() {
  if (on_gadi()) {
    data.frame(
      file = relative_path(zenodo_files()),
      description = "This table of files"
    ) |>
      write.table(zenodo_files(), row.names = FALSE, sep = ",")
  }

  return(invisible(zenodo_files()))
}
