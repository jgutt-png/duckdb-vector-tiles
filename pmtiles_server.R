# PMTiles Vector Tiles with 3D Population Visualization
# This script creates and serves vector tiles using PMTiles format

library(tidycensus)
library(sf)
library(pmtiles)
library(mapgl)
library(dplyr)

# Set Census API key
census_api_key("50076e92f117dd465e96d431111e6b3005f4a9b4")

# 1. Fetch ALL US block group population data
cat("Fetching population data for ALL US block groups...\n")
cat("This may take 5-10 minutes...\n")
us_population <- get_acs(
  geography = "block group",
  variables = "B01003_001",  # Total population
  year = 2022,
  geometry = TRUE
) %>%
  select(
    GEOID,
    NAME,
    population = estimate,
    geometry
  )

cat("Fetched", nrow(us_population), "block groups\n")

# 2. Create PMTiles directly from sf object
pmtiles_file <- "us_population.pmtiles"
cat("Creating PMTiles archive...\n")
cat("This will take several minutes for all US data...\n")

pm_create(
  input = us_population,
  output = pmtiles_file,
  layer_name = "population",
  min_zoom = 0,
  max_zoom = 14
)

cat("PMTiles file created:", pmtiles_file, "\n")

# 3. Create HTML page with 3D visualization
port <- as.integer(Sys.getenv("PORT", "8080"))
cat("Creating map visualization...\n")

map_html <- sprintf('
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>US Population 3D Map</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.js"></script>
  <link href="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.css" rel="stylesheet" />
  <script src="https://unpkg.com/pmtiles@2.11.0/dist/index.js"></script>
  <style>
    body { margin: 0; padding: 0; }
    #map { position: absolute; top: 0; bottom: 0; width: 100%%; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    let protocol = new pmtiles.Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);

    const map = new maplibregl.Map({
      container: "map",
      style: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json",
      center: [-98.5, 39.8],  // US center
      zoom: 4,
      pitch: 60,
      bearing: -17.6
    });

    map.on("load", () => {
      map.addSource("population", {
        type: "vector",
        url: "pmtiles:///%s",
        attribution: "US Census Bureau"
      });

      map.addLayer({
        id: "population-3d",
        type: "fill-extrusion",
        source: "population",
        "source-layer": "population",
        paint: {
          "fill-extrusion-color": [
            "interpolate",
            ["linear"],
            ["get", "population"],
            0, "#f7fbff",
            500, "#deebf7",
            1000, "#c6dbef",
            2000, "#9ecae1",
            3000, "#6baed6",
            4000, "#4292c6",
            5000, "#2171b5",
            7000, "#08519c",
            10000, "#08306b"
          ],
          "fill-extrusion-height": [
            "interpolate",
            ["linear"],
            ["get", "population"],
            0, 0,
            10000, 50000
          ],
          "fill-extrusion-opacity": 0.9
        }
      });

      map.addControl(new maplibregl.NavigationControl(), "top-right");
    });
  </script>
</body>
</html>', pmtiles_file)

# 4. Serve using httpuv
library(httpuv)

app <- list(
  call = function(req) {
    path <- req$PATH_INFO

    # Serve HTML at root
    if (path == "/") {
      return(list(
        status = 200L,
        headers = list(
          "Content-Type" = "text/html; charset=utf-8",
          "Access-Control-Allow-Origin" = "*"
        ),
        body = map_html
      ))
    }

    # Serve PMTiles file
    if (grepl("\\\\.pmtiles$", path)) {
      file_path <- paste0(".", path)
      if (file.exists(file_path)) {
        return(list(
          status = 200L,
          headers = list(
            "Content-Type" = "application/x-protobuf",
            "Access-Control-Allow-Origin" = "*"
          ),
          body = readBin(file_path, "raw", file.info(file_path)$size)
        ))
      }
    }

    # 404 for everything else
    return(list(
      status = 404L,
      headers = list("Content-Type" = "text/plain"),
      body = "Not Found"
    ))
  }
)

cat("Starting server on port", port, "...\n")
cat("Serving US population 3D map at http://0.0.0.0:", port, "/\n", sep = "")

runServer("0.0.0.0", port, app)
