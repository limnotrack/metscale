#' Download ERA5 data from ISIMIP3a for a point location
#'
#' Download daily ERA5 (20CRv3-ERA5, ISIMIP3a `obsclim`) meteorology for a
#' point location, anywhere globally, for the period covered by ISIMIP3a
#' (currently up to 2021). Data are pulled from the
#' \href{https://files.isimip.org/api/v2}{ISIMIP repository API}; no account or
#' key is required.
#'
#' Requires the suggested packages \pkg{httr2}, \pkg{jsonlite} and \pkg{terra}.
#'
#' @param lon numeric; longitude.
#' @param lat numeric; latitude.
#' @param years numeric; vector of years to extract.
#' @param vars character; AEME meteorological variable names to download.
#' Defaults to all available: `c("MET_tmpair", "MET_pprain", "MET_wndspd",
#' "MET_radswd", "MET_prsttn", "MET_radlwd", "MET_humrel")`. ERA5/CMIP short
#' names (`tas`, `pr`, `sfcwind`, `rsds`, `ps`, `rlds`, `hurs`) are also
#' accepted.
#' @param download_path character; path to download the data. Default is the
#' temporary directory.
#'
#' @returns A data frame with a `Date` column and one column per requested
#' variable.
#' @export
#'
#' @examples
#' \dontrun{
#' lon <- 13.064332
#' lat <- 52.380551
#' years <- 2015:2021
#' vars <- c("MET_tmpair", "MET_pprain")
#' download_era5_isimip_point(lon, lat, years, vars)
#' }
download_era5_isimip_point <- function(lon, lat, years,
                                       vars = c("MET_tmpair", "MET_pprain",
                                                "MET_wndspd", "MET_radswd",
                                                "MET_prsttn", "MET_radlwd",
                                                "MET_humrel"),
                                       download_path = tempdir()) {

  for (pkg in c("httr2", "jsonlite", "terra")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("Package '", pkg, "' is required for download_era5_isimip_point(). ",
           "Install it with install.packages('", pkg, "').", call. = FALSE)
    }
  }

  # Timer helpers so the user gets a sense of how long each step takes
  t_start <- Sys.time()
  fmt_dur <- function(since) {
    secs <- as.numeric(difftime(Sys.time(), since, units = "secs"))
    if (secs < 60) {
      sprintf("%.0fs", secs)
    } else if (secs < 3600) {
      sprintf("%.1f min", secs / 60)
    } else {
      sprintf("%.1f h", secs / 3600)
    }
  }

  # ISIMIP API URL
  url <- "https://files.isimip.org/api/v2"

  # Variable checking and mapping
  vars <- check_vars(vars)

  paths <- build_paths(vars, years)

  data <- list(
    paths = paths,
    operations = list(
      list(
        operation = "select_bbox",
        bbox = list(lon - 0.25, lon + 0.25, lat - 0.25, lat + 0.25)
      )
    )
  )

  # Perform the initial request to the server
  cli::cli_alert_info(
    "Submitting job to ISIMIP server ({length(paths)} file{?s} requested)"
  )
  t_submit <- Sys.time()
  req <- httr2::request(url) |>
    httr2::req_body_json(data)

  res <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      cli::cli_alert_danger(
        "Job submission failed after {fmt_dur(t_submit)}: {e$message}"
      )
      return(NULL)
    }
  )

  if (is.null(res)) return(invisible(NULL))

  if (httr2::resp_status(res) >= 200 && httr2::resp_status(res) < 300) {
    job <- httr2::resp_body_json(res)
    cli::cli_alert_success(
      "Job submitted in {fmt_dur(t_submit)} | id={job$id} | status={job$status}"
    )

    # Poll until the server has finished preparing the files
    t_poll <- Sys.time()
    while (job$status %in% c("queued", "started")) {
      Sys.sleep(4)
      job_req <- httr2::request(job$job_url)
      job_res <- httr2::req_perform(job_req)
      job <- httr2::resp_body_json(job_res)

      created <- job$meta$created_files
      total <- job$meta$total_files
      poll_secs <- as.numeric(difftime(Sys.time(), t_poll, units = "secs"))
      # Rough ETA from the file-creation rate observed so far
      eta <- ""
      if (length(total) == 1 && !is.na(total) && length(created) == 1 &&
          !is.na(created) && created > 0 && created < total) {
        remaining <- (total - created) * (poll_secs / created)
        eta <- if (remaining < 60) {
          sprintf(", ~%.0fs left", remaining)
        } else {
          sprintf(", ~%.1f min left", remaining / 60)
        }
      }
      cli::cli_alert_info(
        "Server {job$status}: {created}/{total} files prepared ({fmt_dur(t_poll)} elapsed{eta})"
      )
    }

    if (job$status == "finished") {
      cli::cli_alert_success(
        "Server finished preparing {job$meta$total_files} file{?s} in {fmt_dur(t_poll)}"
      )

      # Download the results archive
      zip_path <- file.path(download_path, job$file_name)
      dir.create(dirname(zip_path), showWarnings = FALSE, recursive = TRUE)
      cli::cli_alert_info("Downloading {job$file_name}")
      t_dl <- Sys.time()
      utils::download.file(job$file_url, zip_path, mode = "wb")
      dl_secs <- as.numeric(difftime(Sys.time(), t_dl, units = "secs"))
      size_mb <- file.size(zip_path) / 1024^2
      dl_rate <- sprintf("%.1f MB/s", size_mb / max(dl_secs, 0.001))
      cli::cli_alert_success(
        "Downloaded {sprintf('%.1f MB', size_mb)} in {fmt_dur(t_dl)} ({dl_rate})"
      )

      # Extract the archive
      out_path <- sub("\\.zip$", "", zip_path)
      dir.create(out_path, showWarnings = FALSE, recursive = TRUE)
      cli::cli_alert_info("Extracting archive to {out_path}")
      t_zip <- Sys.time()
      utils::unzip(zip_path, exdir = out_path)
      n_nc <- length(list.files(out_path, pattern = "\\.nc$"))
      cli::cli_alert_success("Extracted {n_nc} file{?s} in {fmt_dur(t_zip)}")

    } else {
      cli::cli_alert_danger("job did not finish successfully (status {job$status})")
    }
  } else {
    cli::cli_alert_danger("job submission failed: {httr2::resp_body_string(res)}")
  }

  cli::cli_alert_info("Reading {length(vars)} variable{?s} from NetCDF files")
  t_read <- Sys.time()
  out <- lapply(vars, \(v) {
    t_v <- Sys.time()
    fils <- list.files(out_path, full.names = TRUE, pattern = paste0("_", v, "_"))
    df <- lapply(fils, \(f) {
      suppressWarnings({
        nc <- terra::rast(f)
      })
      vals <- terra::values(nc)
      dates <- terra::time(nc)
      data.frame(Date = dates, value = as.vector(vals))
    }) |>
      dplyr::bind_rows()
    names(df) <- c("Date", v)
    cli::cli_alert_info(
      "  {v}: {length(fils)} file{?s}, {nrow(df)} record{?s} ({fmt_dur(t_v)})"
    )
    return(df)
  })
  cli::cli_alert_success("Read all variables in {fmt_dur(t_read)}")

  # Join all data frames by the "Date" column
  result <- Reduce(function(x, y) dplyr::full_join(x, y, by = "Date"), out)

  # Unit conversions
  # If "tas" is present, convert from K to C
  if ("tas" %in% colnames(result)) {
    result$tas <- result$tas - 273.15
  }

  # If "pr" is present, convert from kg m-2 s-1 to mm/day
  if ("pr" %in% colnames(result)) {
    result$pr <- result$pr * 86400
  }

  # Rename to AEME column names
  names(result) <- switch_vars(names(result))

  cli::cli_alert_success(
    "Done: {nrow(result)} daily record{?s} for {length(vars)} variable{?s} (total {fmt_dur(t_start)})"
  )

  return(result)
}

#' Check and map variable names
#'
#' @param vars A character vector of variable names
#' @return A vector of variable names suitable for ISIMIP3a
#' @noRd
check_vars <- function(vars) {

  # Reference data frame for variable mapping
  vars_df <- data.frame(
    era5 = c("tas", "pr", "sfcwind", "rsds", "ps", "rlds", "hurs"),
    aeme = c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd",
             "MET_prsttn", "MET_radlwd", "MET_humrel")
  )

  aeme_chk <- grepl("^MET_", vars)
  if (any(aeme_chk)) {
    if (!all(aeme_chk)) stop("Mixing of ERA5 and AEME variables is not allowed")
    vars <- vars_df |>
      dplyr::filter(aeme %in% vars) |>
      # arrange in the same order as vars
      dplyr::arrange(match(vars, aeme)) |>
      dplyr::pull(era5)
  } else {
    if (!all(vars %in% vars_df$era5)) stop("Invalid variable(s)")
  }
  if (length(vars) == 0) stop("No valid variables")
  return(vars)
}

#' Switch variable names
#'
#' @param vars A character vector of variable names
#' @return A vector of variable names suitable for ISIMIP3a or AEME
#' @noRd
switch_vars <- function(vars) {

  # Reference data frame for variable mapping
  mapping_df <- data.frame(
    era5 = c("tas", "pr", "sfcwind", "rsds", "ps", "rlds", "hurs"),
    aeme = c("MET_tmpair", "MET_pprain", "MET_wndspd", "MET_radswd",
             "MET_prsttn", "MET_radlwd", "MET_humrel")
  )
  # Create a named vector for mapping
  era5_to_aeme <- stats::setNames(mapping_df$aeme, mapping_df$era5)
  aeme_to_era5 <- stats::setNames(mapping_df$era5, mapping_df$aeme)

  aeme_chk <- grepl("^MET_", vars)
  if (any(aeme_chk)) {
    upd_vars <- sapply(vars, function(x) {
      if (x %in% names(aeme_to_era5)) aeme_to_era5[[x]] else x
    }, USE.NAMES = FALSE)
  } else {
    upd_vars <- sapply(vars, function(x) {
        if (x %in% names(era5_to_aeme)) era5_to_aeme[[x]] else x
      }, USE.NAMES = FALSE)
  }

  return(upd_vars)
}


#' Get decades for a given year for ISIMIP3a data
#'
#' @param years A numeric vector of years
#' @return A vector of decades
#' @noRd
get_decades <- function(years) {
  # Ensure the input is numeric
  years <- as.numeric(years)

  # Initialize a vector to store the results
  decades <- c()

  for (year in years) {
    if (year %% 10 == 1 && year > 2000) {
      # Handle single-year case (e.g., 2021)
      decade_str <- paste0(year, "_", year)
    } else {
      # Calculate the start of the decade
      decade_start <- floor((year - 1) / 10) * 10 + 1
      # Calculate the end of the decade
      decade_end <- decade_start + 9
      # Combine into a string
      decade_str <- paste0(decade_start, "_", decade_end)
    }
    decades <- c(decades, decade_str)
  }

  # Return unique decades
  return(unique(decades))
}

#' Build paths for ISIMIP3a data
#'
#' @param vars A character vector of variable names
#' @param years A numeric vector of years
#' @return A list of paths
#' @noRd
build_paths <- function(vars, years) {
  # Get the decades for the years
  decades <- get_decades(years)

  path_list <- lapply(vars, \(v) {
    paste0("ISIMIP3a/InputData/climate/atmosphere/obsclim/global/daily/historical/20CRv3-ERA5/20crv3-era5_obsclim_",
           v, "_global_daily_", decades, ".nc")
  })
  vec <- unlist(path_list)
  lst <- as.list(vec)
  return(lst)
}
