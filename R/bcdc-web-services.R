# Copyright 2018 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and limitations under the License.


#' Query data from the B.C. Web Service
#'
#' Queries features from the B.C. Web Service. The data must be available as
#' a Web Service. See `bcdc_get_record(record)$resources`). The response will
#' be paginated if the number of features is above the number set by the
#' `bcdata.single_download_limit` option. Please see [bcdc_options()] for defaults
#' and more information.
#'
#' Note that this function doesn't actually return the data, but rather an
#' object of class `bcdc_promise`, which includes all of the information
#' required to retrieve the requested data. In order to get the actual data as
#' an `sf` object, you need to run [collect()] on the `bcdc_promise`. This
#' allows further refining the call to `bcdc_query_geodata()` with [filter()]
#' and/or [select()] statements before pulling down the actual data as an `sf`
#' object with [collect()]. See examples.
#'
#' @inheritParams bcdc_get_data
#' @param crs the epsg code for the coordinate reference system. Defaults to
#'   `3005` (B.C. Albers). See https://epsg.io.
#'
#' @return A `bcdc_promise` object. This object includes all of the information
#'   required to retrieve the requested data. In order to get the actual data as
#'   an `sf` object, you need to run [collect()] on the `bcdc_promise`.
#'
#' @export
#'
#' @examples
#'
#' \donttest{
#' # Returns a bcdc_promise, which can be further refined using filter/select:
#' try(
#'   bcdc_query_geodata("bc-airports", crs = 3857)
#' )
#'
#' # To obtain the actual data as an sf object, collect() must be called:
#' try(
#'   bcdc_query_geodata("bc-airports", crs = 3857) %>%
#'     filter(PHYSICAL_ADDRESS == 'Victoria, BC') %>%
#'     collect()
#' )
#'
#' try(
#'   bcdc_query_geodata("groundwater-wells") %>%
#'     filter(OBSERVATION_WELL_NUMBER == "108") %>%
#'     select(WELL_TAG_NUMBER, INTENDED_WATER_USE) %>%
#'     collect()
#' )
#'
#' ## A moderately large layer
#' try(
#'   bcdc_query_geodata("bc-environmental-monitoring-locations")
#' )
#'
#' try(
#'   bcdc_query_geodata("bc-environmental-monitoring-locations") %>%
#'     filter(PERMIT_RELATIONSHIP == "DISCHARGE")
#' )
#'
#'
#' ## A very large layer
#' try(
#'   bcdc_query_geodata("terrestrial-protected-areas-representation-by-biogeoclimatic-unit")
#' )
#'
#' ## Using a BCGW name
#' try(
#'   bcdc_query_geodata("WHSE_IMAGERY_AND_BASE_MAPS.GSR_AIRPORTS_SVW")
#' )
#' }
#' @export
bcdc_query_geodata <- function(record, crs = 3005) {
  if (!has_internet()) stop("No access to internet", call. = FALSE) # nocov
  UseMethod("bcdc_query_geodata")
}

#' @export
bcdc_query_geodata.default <- function(record, crs = 3005) {
  stop("No bcdc_query_geodata method for an object of class ", class(record),
       call. = FALSE)
}

#' @export
bcdc_query_geodata.character <- function(record, crs = 3005) {

  if (length(record) != 1) {
    stop("Only one record my be queried at a time.", call. = FALSE)
  }

  # Fist catch if a user has passed the name of a warehouse object directly,
  # then can skip all the record parsing and make the API call directly
  if (is_whse_object_name(record)) {
    ## Parameters for the API call
    query_list <- make_query_list(layer_name = record, crs = crs)

    ## Drop any NULLS from the list
    query_list <- compact(query_list)

    ## GET and parse data to sf object
    cli <- bcdc_wfs_client()

    cols_df <- feature_helper(record)

    return(
      as.bcdc_promise(list(query_list = query_list, cli = cli, record = NULL,
                           cols_df = cols_df))
    )
  }

  if (grepl("/resource/", record)) {
    #  A full url was passed including record and resource compenents.
    # Grab the resource id and strip it off the url
    record <- gsub("/resource/.+", "", record)
  }

  obj <- bcdc_get_record(record)

  bcdc_query_geodata(obj, crs)
}

#' @export
bcdc_query_geodata.bcdc_record <- function(record, crs = 3005) {
  if (!any(wfs_available(record$resource_df))) {
    stop("No Web Service resource available for this data set.",
         call. = FALSE
    )
  }

  layer_name <- basename(dirname(
    record$resource_df$url[record$resource_df$format == "wms"]
  ))

  ## Parameters for the API call
  query_list <- make_query_list(layer_name = layer_name, crs = crs)

  ## Drop any NULLS from the list
  query_list <- compact(query_list)

  ## GET and parse data to sf object
  cli <- bcdc_wfs_client()

  cols_df <- feature_helper(query_list$typeNames)

  as.bcdc_promise(list(query_list = query_list, cli = cli, record = record,
                       cols_df = cols_df))
}

#' Get map from the B.C. Web Service
#'
#'
#' @inheritParams bcdc_get_data
#'
#' @examples
#' \donttest{
#' try(
#'   bcdc_preview("regional-districts-legally-defined-administrative-areas-of-bc")
#' )
#'
#' try(
#'   bcdc_preview("points-of-well-diversion-applications")
#' )
#'
#' # Using BCGW name
#' try(
#'   bcdc_preview("WHSE_LEGAL_ADMIN_BOUNDARIES.ABMS_REGIONAL_DISTRICTS_SP")
#' )
#' }
#' @export
bcdc_preview <- function(record) { # nocov start
  if (!has_internet()) stop("No access to internet", call. = FALSE)
  UseMethod("bcdc_preview")
}

#' @export
bcdc_preview.default <- function(record) {
  stop("No bcdc_preview method for an object of class ", class(record),
       call. = FALSE)
}

#' @export
bcdc_preview.character <- function(record) {

  if (is_whse_object_name(record)) {
    make_wms(record)
  } else {
    bcdc_preview(bcdc_get_record(record))
  }
}

#' @export
bcdc_preview.bcdc_record <- function(record) {

  make_wms(record$layer_name)

}

make_wms <- function(x){
  wms_url <- "http://openmaps.gov.bc.ca/geo/pub/wms"
  wms_options <- leaflet::WMSTileOptions(format = "image/png",
                                         transparent = TRUE,
                                         attribution = "BC Data Catalogue (https://catalogue.data.gov.bc.ca/)")
  wms_legend <- glue::glue("{wms_url}?request=GetLegendGraphic&
             format=image%2Fpng&
             width=20&
             height=20&
             layer=pub%3A{x}")

  leaflet::leaflet() %>%
    leaflet::addProviderTiles(leaflet::providers$CartoDB.DarkMatter,
                              options = leaflet::providerTileOptions(noWrap = TRUE)) %>%
    leaflet::addWMSTiles(wms_url,
                         layers=glue::glue("pub:{x}"),
                         options = wms_options) %>%
    leaflet.extras::addWMSLegend(uri = wms_legend) %>%
    leaflet::setView(lng = -126.5, lat = 54.5, zoom = 5)
} # nocov end


make_query_list <- function(layer_name, crs) {
  list(
    SERVICE = "WFS",
    VERSION = "2.0.0",
    REQUEST = "GetFeature",
    outputFormat = "application/json",
    typeNames = layer_name,
    SRSNAME = paste0("EPSG:", crs)
  )
}

