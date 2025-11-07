# PMTiles Vector Tiles with 3D Population Visualization
# This script creates and serves vector tiles using PMTiles format

library(tidycensus)
library(sf)
library(pmtiles)
library(mapgl)
library(dplyr)

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

# 2. Write to GeoJSON (tippecanoe input format)
geojson_file <- "tx_population.geojson"
cat("Writing GeoJSON file...\n")
st_write(tx_population, geojson_file, delete_dsn = TRUE, quiet = TRUE)

# 3. Convert to PMTiles using tippecanoe
pmtiles_file <- "tx_population.pmtiles"
cat("Creating PMTiles archive...\n")

pm_tiles(
  input = geojson_file,
  output = pmtiles_file,
  name = "Texas Population",
  layer = "population",
  minzoom = 0,
  maxzoom = 14,
  drop_densest_as_needed = TRUE,
  extend_zooms_if_still_dropping = TRUE
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
