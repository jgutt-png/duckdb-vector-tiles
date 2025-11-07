# PMTiles Vector Tiles with 3D Population Visualization
# This script creates and serves vector tiles using PMTiles format

library(tidycensus)
library(sf)
library(pmtiles)
library(mapgl)
library(dplyr)

# Set Census API key
census_api_key("50076e92f117dd465e96d431111e6b3005f4a9b4")

# 1. Fetch Texas block group population data
cat("Fetching population data for Texas block groups...\n")
tx_population <- get_acs(
  geography = "block group",
  variables = "B01003_001",  # Total population
  state = "TX",
  year = 2022,
  geometry = TRUE
) %>%
  select(
    GEOID,
    NAME,
    population = estimate,
    geometry
  )

cat("Fetched", nrow(tx_population), "block groups\n")

# 2. Create PMTiles directly from sf object
pmtiles_file <- "tx_population.pmtiles"
cat("Creating PMTiles archive...\n")

pm_create(
  input = tx_population,
  output = pmtiles_file,
  layer_name = "population",
  min_zoom = 0,
  max_zoom = 14
)

cat("PMTiles file created:", pmtiles_file, "\n")

# 4. Serve tiles and create 3D visualization
port <- as.integer(Sys.getenv("PORT", "8080"))
cat("Starting PMTiles server on port", port, "...\n")

# Create the 3D map visualization
map <- maplibre(
  style = carto_style("positron"),
  center = c(-99.9, 31.5),  # Texas center
  zoom = 6,
  pitch = 60,
  bearing = -17.6
) %>%
  add_pmtiles_source(
    source_id = "tx_population",
    url = pmtiles_file,
    layer = "population"
  ) %>%
  add_fill_extrusion_layer(
    id = "population-3d",
    source = "tx_population",
    fill_extrusion_color = interpolate(
      column = "population",
      values = c(0, 500, 1000, 2000, 3000, 4000, 5000, 7000, 10000),
      stops = c("#f7fbff", "#deebf7", "#c6dbef", "#9ecae1", "#6baed6",
                "#4292c6", "#2171b5", "#08519c", "#08306b")
    ),
    fill_extrusion_height = interpolate(
      column = "population",
      values = c(0, 10000),
      stops = c(0, 50000)
    ),
    fill_extrusion_opacity = 0.9
  )

# 5. Serve the map with PMTiles
cat("Serving 3D population map at http://0.0.0.0:", port, "/\n", sep = "")

pm_serve(
  pmtiles = pmtiles_file,
  map = map,
  port = port,
  host = "0.0.0.0"
)
