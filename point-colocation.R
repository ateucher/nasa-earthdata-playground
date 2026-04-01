library(sf)
library(stars)
library(earthdatalogin)
library(lubridate)
library(dplyr)

url <- "https://raw.githubusercontent.com/fish-pace/point-collocation/main/examples/fixtures/points.csv"
df_points <- read_sf(
  url,
  options = c("X_POSSIBLE_NAMES=lon", "Y_POSSIBLE_NAMES=lat"),
  crs = 4326
) |>
  mutate(date = ymd(date))

edl_netrc()

granules <- edl_search(
  short_name = "PACE_OCI_L3M_RRS",
  temporal = as.character(c(
    min(df_points$date),
    max(df_points$date)
  )),
  bounding_box = st_bbox(df_points),
  parse = FALSE
)

edl_extract_urls(granules) |>
  grep("*.MO.*.4km.*", x = _, value = TRUE)

sf::gdal_utils(
  "mdiminfo",
  paste0("/vsicurl/", granules[1])
)

rrs <- read_mdim(
  paste0("/vsicurl/", granules),
  array_name = "//Rrs",
  driver = if (Sys.info()["sysname"] %in% c("Windows", "Darwin")) {
    "HDF5"
  } else {
    "netCDF"
  },
  proxy = TRUE
)

st_crs(rrs) <- 4326

# Build a bounding box with a small buffer around your points
bbox <- df_points |>
  st_bbox() |>
  st_as_sfc() |>
  st_buffer(1) |> # 1 degree buffer
  st_bbox()

# Crop first - this stays lazy (proxy), no data read yet
rrs_crop <- rrs[bbox]

# # Materialise only the small cropped region
# rrs_stars <- st_as_stars(rrs_crop)

# # Extract dates from granule names — the YYYYMMDD_YYYYMMDD pattern
# dates <- stringr::str_extract(names(rrs_stars), "\\d{8}") |>
#   ymd()

# # 3. Now set dimensions on the materialised object
# rrs_stars <- st_set_dimensions(rrs_stars, "time", values = dates, point = FALSE)

# st_dimensions(rrs_stars)

# Now extract - only the cropped region is loaded
st_extract(rrs_crop, at = df_points, time_column = "date")
