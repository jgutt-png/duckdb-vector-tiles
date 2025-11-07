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
# Find available port (starting from 8000)
find_available_port <- function(start_port = 8000, max_attempts = 10) {
  for (i in 0:(max_attempts - 1)) {
    port <- start_port + i
    tryCatch(
      {
        # Try to start server on this port
        test_server <- startServer(
          "127.0.0.1",
          port,
          list(call = function(req) {
            list(status = 200L, body = "test")
          })
        )
        stopServer(test_server)
        return(port)
      },
      error = function(e) {
        # Port is in use, try next one
      }
    )
  }
  stop("Could not find available port")
}

port <- find_available_port()
cat("Starting tile server on port", port, "\n")

# Start the server in the background
server <- startDaemonizedServer("127.0.0.1", port, tile_app)

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

# 5. Create the mapgl map with the DuckDB vector tile source
m <- maplibre(
  center = c(-79.5, 35.5),
  zoom = 6,
  style = carto_style("positron")
) |>
  add_vector_source(
    id = "duckdb-tiles",
    tiles = paste0("http://127.0.0.1:", port, "/tiles/{z}/{x}/{y}.pbf"),
    minzoom = 0,
    maxzoom = 14,
    promote_id = "GEOID"
  ) |>
  add_fill_layer(
    id = "features-fill",
    source = "duckdb-tiles",
    source_layer = "layer", # ST_AsMVT default layer name
    fill_color = "steelblue",
    fill_opacity = 0.6,
    tooltip = "GEOID",
    hover_options = list(
      fill_color = "yellow",
      fill_opacity = 1
    )
  ) |>
  add_line_layer(
    id = "features-line",
    source = "duckdb-tiles",
    source_layer = "layer",
    line_color = "white",
    line_width = 1
  )

# Display the map
m

# Cleanup function (run this when done)
cleanup_tile_server <- function() {
  if (exists("tile_server_info")) {
    stopDaemonizedServer(tile_server_info$server)
    dbDisconnect(tile_server_info$con)
    cat("Tile server stopped and database disconnected\n")
  }
}

# Note: To stop the server and disconnect, run:
# cleanup_tile_server()
