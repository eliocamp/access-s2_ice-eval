# Minimal Zenodo helpers for a single fixed deposition
# Uses httr2 for HTTP requests. Keep this file small and focused.

# Hard-coded deposition ID for this project. Replace with the real ID.
ZENODO_DEPOSITION_ID <- 386004

# Internal: read the token from environment and validate
.zenodo_get_token <- function() {
  token <- Sys.getenv("ZENODO_TOKEN", unset = "")
  if (identical(token, "") || is.na(token)) {
    stop(
      "ZENODO_TOKEN environment variable is not set or empty. Set it to your Zenodo API token."
    )
  }
  token
}

# Internal: choose base API URL. If ZENODO_SANDBOX is set (non-empty), use the sandbox API.
.zenodo_base_url <- function() {
  if (nzchar(Sys.getenv("ZENODO_SANDBOX", ""))) {
    return("https://sandbox.zenodo.org/api")
  }
  "https://zenodo.org/api"
}

# List files attached to the fixed deposition
# Returns a list (as returned by the API) or throws on error
zenodo_list_files <- function(deposition_id = ZENODO_DEPOSITION_ID) {
  token <- .zenodo_get_token()
  url <- paste0(.zenodo_base_url(), "/deposit/depositions/", deposition_id)

  resp <- httr2::request(url) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop(sprintf(
      "Zenodo API returned HTTP %s: %s",
      httr2::resp_status(resp),
      httr2::resp_body_json(resp, simplifyVector = TRUE)$message
    ))
  }

  body <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  # body$files is typically a list with elements containing 'filename', 'id', 'links', etc.
  body$files
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


# Upload a local file to the fixed deposition.
# Returns the API response for the uploaded file entry.
zenodo_upload_file <- function(path, deposition_id = ZENODO_DEPOSITION_ID) {
  if (!file.exists(path)) {
    stop("File does not exist: ", path)
  }
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

  remote_files <- zenodo_list_files() |>
    vapply(\(x) x$filename, character(1))

  if (!("checksum" %in% remote_files)) {
    return(list(
      local = checksum_local,
      checksum = NULL,
      matches = FALSE
    ))
  }

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

zenodo_upload_data <- function() {
  files <- read.csv(zenodo_files())

  files <- files[!duplicated(files$file), ]

  if (nrow(files) == 0) {
    stop("No files in zenodo_files.txt")
  }

  checksum <- zenodo_checksum_matches(files$files)

  if (checksum$matches) {
    message("Remote and local checksum match. Nothing to upload.")
    return(invisible(NULL))
  }

  message("Creating zip file")
  zipfile <- file.path(tempdir(), "data.zip")
  zip(zipfile, files$file)

  message("Uploading zip file")
  zenodo_upload_file(zipfile)

  message("Uploading checksum file")
  checksum_file <- here::here("data/checksum")
  writeLines(checksum$local, checksum_file)
  zenodo_upload_file(checksum_file)
}

# Download a file (by filename) from the fixed deposition to a local path.
# If destination is a directory, the file will be saved inside it with the original filename.
zenodo_download_file <- function(
  filename,
  dest = ".",
  deposition_id = ZENODO_DEPOSITION_ID
) {
  token <- .zenodo_get_token()

  files <- zenodo_list_files(deposition_id = deposition_id)
  # find by exact filename
  match <- NULL
  for (f in files) {
    if (!is.null(f$filename) && identical(f$filename, filename)) {
      match <- f
      break
    }
  }
  if (is.null(match)) {
    stop("File not found in deposition: ", filename)
  }

  # download link is usually in match$links$download
  dl <- match$links$download
  if (is.null(dl)) {
    stop("No download link available for file: ", filename)
  }

  resp <- httr2::request(dl) |>
    httr2::req_auth_bearer_token(token) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop(sprintf("Failed to download file: HTTP %s", httr2::resp_status(resp)))
  }

  data <- httr2::resp_body_raw(resp)

  # determine destination path
  if (dir.exists(dest)) {
    destfile <- file.path(dest, filename)
  } else {
    # if dest ends with a separator or looks like a directory that doesn't exist, treat as dir
    destfile <- dest
  }

  con <- file(destfile, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(data, con)

  invisible(destfile)
}


zenodo_download_data <- function() {
  if (on_gadi()) {
    return(invisible(NULL))
  }

  file_list <- zenodo_files()

  if (file.exists(file_list)) {
    needed_files <- read.csv(file_list)$file |>
      Filter(f = nzchar)

    if (all(file.exists(needed_files))) {
      checksum <- zenodo_checksum_matches(needed_files)
      if (checksum$matches) return(invisible(NULL))
    }
  }

  dir <- tempdir()
  file <- zenodo_download_file("data.zip", dir)
  unzip(file, exdtir = here::here(""))

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
  dir.create(dirname(file_path), showWarnings = FALSE, recurseive = TRUE)
  return(file_path)
}

zenodo_files <- function() {
  here::here("data/zenodo_files.csv") |>
    create_dir()
}


zenodo_init <- function() {
  data.frame(
    file = relative_path(zenodo_files()),
    description = "This table of files"
  ) |>
    write.table(zenodo_files(), row.names = FALSE, sep = ",") |>
    invisible()
}

## End of zenodo helpers
