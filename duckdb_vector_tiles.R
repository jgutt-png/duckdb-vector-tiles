# DuckDB Vector Tiles with mapgl Example
# This script demonstrates how to serve vector tiles from DuckDB using ST_AsMVT()
# and display them in a mapgl map using httpuv

library(mapgl)
library(duckdb) # Requires the latest DuckDB version (>= 1.4.0)
library(httpuv)
library(sf)
library(duckspatial)
library(tigris)

# 1. Setup DuckDB connection and load spatial extension
con <- dbConnect(duckdb::duckdb(), dbdir = "tiles.duckdb")
ddbs_install(con)
ddbs_load(con)

# 2. Load your spatial data into DuckDB
# Example: Load an sf object into DuckDB and transform to Web Mercator (EPSG:3857)
# All US block groups: 242,000 polygons
data <- block_groups(cb = TRUE)

# Transform to Web Mercator for tiling
data_mercator <- st_transform(data, 3857)

# Write to DuckDB using duckspatial
ddbs_write_vector(con, data_mercator, "features", overwrite = TRUE)

# Optional: Create a spatial index for better performance
dbExecute(con, "CREATE INDEX idx_geom ON features USING RTREE (geometry)")

# 3. Create a lightweight httpuv server for serving tiles

# Helper function to parse tile coordinates from URL path
parse_tile_path <- function(path) {
  # Match pattern: /tiles/{z}/{x}/{y}.pbf
  pattern <- "^/tiles/(\\d+)/(\\d+)/(\\d+)\\.pbf$"
  matches <- regmatches(path, regexec(pattern, path))[[1]]

  if (length(matches) == 4) {
    list(
      z = as.integer(matches[2]),
      x = as.integer(matches[3]),
      y = as.integer(matches[4])
    )
  } else {
    NULL
  }
}

# Create the httpuv application
tile_app <- list(
  call = function(req) {
    path <- req$PATH_INFO

    # Handle CORS preflight requests
    if (req$REQUEST_METHOD == "OPTIONS") {
      return(list(
        status = 200L,
        headers = list(
          'Access-Control-Allow-Origin' = '*',
          'Access-Control-Allow-Methods' = 'GET, OPTIONS',
          'Access-Control-Allow-Headers' = '*'
        ),
        body = ""
      ))
    }

    # Serve map HTML at root
    if (path == "/") {
      port <- as.integer(Sys.getenv("PORT", "8080"))
      host <- Sys.getenv("RAILWAY_PUBLIC_DOMAIN", "localhost")
      base_url <- if (host == "localhost") {
        paste0("http://", host, ":", port)
      } else {
        paste0("https://", host)
      }

      map_html <- sprintf('
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>DuckDB Vector Tiles Demo</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.js"></script>
  <link href="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.css" rel="stylesheet" />
  <style>
    body { margin: 0; padding: 0; }
    #map { position: absolute; top: 0; bottom: 0; width: 100%%; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    const map = new maplibregl.Map({
      container: "map",
      style: "https://basemaps.cartocdn.com/gl/positron-gl-style/style.json",
      center: [-79.5, 35.5],
      zoom: 6
    });

    map.on("load", () => {
      map.addSource("duckdb-tiles", {
        type: "vector",
        tiles: ["%s/tiles/{z}/{x}/{y}.pbf"],
        minzoom: 0,
        maxzoom: 14
      });

      map.addLayer({
        id: "features-fill",
        type: "fill",
        source: "duckdb-tiles",
        "source-layer": "layer",
        paint: {
          "fill-color": "steelblue",
          "fill-opacity": 0.6
        }
      });

      map.addLayer({
        id: "features-line",
        type: "line",
        source: "duckdb-tiles",
        "source-layer": "layer",
        paint: {
          "line-color": "white",
          "line-width": 1
        }
      });
    });
  </script>
</body>
</html>', base_url)

      return(list(
        status = 200L,
        headers = list(
          'Content-Type' = 'text/html; charset=utf-8',
          'Access-Control-Allow-Origin' = '*'
        ),
        body = map_html
      ))
    }

    # Parse tile coordinates from URL
    tile_coords <- parse_tile_path(path)

    if (!is.null(tile_coords)) {
      # Query DuckDB for the tile
      tile_query <- "
        SELECT ST_AsMVT(mvt_geom, 'layer')
        FROM (
          SELECT
            GEOID,
            NAME,
            ST_AsMVTGeom(
              geometry,
              (SELECT ST_Extent(ST_TileEnvelope(?, ?, ?)))
            ) AS geometry
          FROM features
          WHERE ST_Intersects(geometry, ST_TileEnvelope(?, ?, ?))
        ) AS mvt_geom
      "

      tryCatch(
        {
          result <- dbGetQuery(
            con,
            tile_query,
            params = list(
              tile_coords$z,
              tile_coords$x,
              tile_coords$y,
              tile_coords$z,
              tile_coords$x,
              tile_coords$y
            )
          )

          # Extract tile blob
          tile_blob <- if (!is.null(result[[1]][[1]])) {
            result[[1]][[1]]
          } else {
            raw(0)
          }

          # Return successful response
          list(
            status = 200L,
            headers = list(
              'Content-Type' = 'application/x-protobuf',
              'Access-Control-Allow-Origin' = '*' # Enable CORS
            ),
            body = tile_blob
          )
        },
        error = function(e) {
          # Return error response
          list(
            status = 500L,
            headers = list(
              'Content-Type' = 'text/plain',
              'Access-Control-Allow-Origin' = '*'
            ),
            body = paste("Error generating tile:", e$message)
          )
        }
      )
    } else {
      # Return 404 for non-tile requests
      list(
        status = 404L,
        headers = list(
          'Content-Type' = 'text/plain',
          'Access-Control-Allow-Origin' = '*'
        ),
        body = "Not Found"
      )
    }
  }
)

# 4. Start the tile server
# Use PORT environment variable (for Railway/cloud deployment) or default to 8080
port <- as.integer(Sys.getenv("PORT", "8080"))
cat("Starting tile server on port", port, "\n")

# Start the server - bind to 0.0.0.0 for external access
server <- startDaemonizedServer("0.0.0.0", port, tile_app)

# Store server info for cleanup
tile_server_info <- list(
  server = server,
  port = port,
  con = con
)

cat("Tile server running at http://127.0.0.1:", port, "/\n", sep = "")
cat(
  "Tiles available at: http://127.0.0.1:",
  port,
  "/tiles/{z}/{x}/{y}.pbf\n",
  sep = ""
)

# Keep the server running
cat("Tile server is running!\n")
cat("Access the map at the root URL of this deployment\n")

# In a production server, we need to keep the process alive
# The map will be served at the root URL
# Use httpuv::service() to process incoming requests
while(TRUE) {
  httpuv::service()  # Process any pending HTTP requests
  Sys.sleep(0.1)     # Short sleep to avoid busy-waiting
}
