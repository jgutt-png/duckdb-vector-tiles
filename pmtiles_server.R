# PMTiles Vector Tiles with 3D Population Visualization
# This script creates and serves vector tiles using PMTiles format

library(tidycensus)
library(sf)
library(pmtiles)
library(dplyr)
library(httpuv)

# Set Census API key and enable caching (optimization from umich workshop)
census_api_key("50076e92f117dd465e96d431111e6b3005f4a9b4")
options(tigris_use_cache = TRUE)  # Cache shapefiles for faster subsequent runs

# 1. Check if PMTiles file already exists (persistent volume caching)
pmtiles_file <- "us_population.pmtiles"

if (file.exists(pmtiles_file)) {
  cat("Found existing PMTiles file - skipping data fetch!\n")
  cat("File size:", round(file.info(pmtiles_file)$size / 1024 / 1024, 2), "MB\n")
} else {
  cat("No cached data found - fetching from Census API...\n")
  cat("This will take 10-15 minutes (one-time only)...\n")

  # List of all US states + DC and PR
  states <- c(state.abb, "DC", "PR")

  # Fetch data for each state and combine
  us_population <- NULL
  for (state in states) {
    cat("Fetching", state, "...\n")
    tryCatch({
      state_data <- get_acs(
        geography = "block group",
        variables = c(
          population = "B01003_001",  # Total population
          income = "B19013_001"       # Median household income
        ),
        state = state,
        year = 2023,  # Latest available ACS data
        geometry = TRUE,
        output = "wide"
      ) %>%
        select(
          GEOID,
          NAME,
          population = populationE,
          income = incomeE,
          geometry
        )

      if (is.null(us_population)) {
        us_population <- state_data
      } else {
        us_population <- rbind(us_population, state_data)
      }

      cat("  Fetched", nrow(state_data), "block groups from", state, "\n")
    }, error = function(e) {
      cat("  Skipping", state, "- error:", e$message, "\n")
    })
  }

  cat("Total:", nrow(us_population), "block groups fetched\n")

  # 2. Create PMTiles file
  cat("Creating PMTiles archive...\n")
  pm_create(
    input = us_population,
    output = pmtiles_file,
    layer_name = "population",
    min_zoom = 0,
    max_zoom = 14
  )

  cat("PMTiles file created:", pmtiles_file, "\n")
  cat("File size:", round(file.info(pmtiles_file)$size / 1024 / 1024, 2), "MB\n")
  cat("Future deployments will use this cached file!\n")
}

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
    #controls {
      position: absolute;
      top: 10px;
      left: 10px;
      background: white;
      padding: 10px;
      border-radius: 4px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      z-index: 1;
    }
    #legend {
      position: absolute;
      bottom: 30px;
      right: 10px;
      background: white;
      padding: 15px;
      border-radius: 4px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      z-index: 1;
      font-family: Arial, sans-serif;
      font-size: 12px;
    }
    #legend h4 {
      margin: 0 0 10px 0;
      font-size: 14px;
    }
    .legend-item {
      display: flex;
      align-items: center;
      margin: 5px 0;
    }
    .legend-color {
      width: 30px;
      height: 15px;
      margin-right: 8px;
      border: 1px solid #ccc;
    }
    button {
      margin: 5px;
      padding: 8px 16px;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 14px;
    }
    button.active {
      background: #2171b5;
      color: white;
    }
    button:not(.active) {
      background: #f0f0f0;
    }
    .maplibregl-popup-content {
      padding: 10px;
      font-family: Arial, sans-serif;
    }
    .popup-label {
      font-weight: bold;
      color: #333;
    }
  </style>
</head>
<body>
  <div id="controls">
    <div>
      <button id="btn-population" class="active" onclick="showLayer(\\"population\\")">Population</button>
      <button id="btn-income" onclick="showLayer(\\"income\\")">Income</button>
    </div>
    <div style="margin-top: 10px;">
      <button id="btn-3d" class="active" onclick="toggle3D(true)">3D</button>
      <button id="btn-2d" onclick="toggle3D(false)">2D</button>
    </div>
  </div>
  <div id="legend">
    <h4 id="legend-title">Population</h4>
    <div id="population-legend">
      <div class="legend-item"><div class="legend-color" style="background: #08306b;"></div><span>10,000+</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #08519c;"></div><span>7,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #2171b5;"></div><span>5,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #4292c6;"></div><span>4,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #6baed6;"></div><span>3,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #9ecae1;"></div><span>2,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #c6dbef;"></div><span>1,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #deebf7;"></div><span>500</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #f7fbff;"></div><span>0</span></div>
    </div>
    <div id="income-legend" style="display: none;">
      <div class="legend-item"><div class="legend-color" style="background: #004529;"></div><span>$200,000+</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #006837;"></div><span>$150,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #238443;"></div><span>$130,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #41ab5d;"></div><span>$110,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #78c679;"></div><span>$90,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #addd8e;"></div><span>$70,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #d9f0a3;"></div><span>$50,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #f7fcb9;"></div><span>$30,000</span></div>
      <div class="legend-item"><div class="legend-color" style="background: #ffffe5;"></div><span>$0</span></div>
    </div>
  </div>
  <div id="map"></div>
  <script>
    let protocol = new pmtiles.Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);

    // Track current layer for tooltips (global scope)
    let currentLayer = "population";

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

      // Population layer (blue)
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

      // Income layer (green/yellow - hidden by default)
      map.addLayer({
        id: "income-3d",
        type: "fill-extrusion",
        source: "population",
        "source-layer": "population",
        layout: {
          "visibility": "none"
        },
        paint: {
          "fill-extrusion-color": [
            "interpolate",
            ["linear"],
            ["get", "income"],
            0, "#ffffe5",
            30000, "#f7fcb9",
            50000, "#d9f0a3",
            70000, "#addd8e",
            90000, "#78c679",
            110000, "#41ab5d",
            130000, "#238443",
            150000, "#006837",
            200000, "#004529"
          ],
          "fill-extrusion-height": [
            "interpolate",
            ["linear"],
            ["get", "income"],
            0, 0,
            200000, 100000
          ],
          "fill-extrusion-opacity": 0.9
        }
      });

      map.addControl(new maplibregl.NavigationControl(), "top-right");

      // Add hover tooltip
      const popup = new maplibregl.Popup({
        closeButton: false,
        closeOnClick: false,
        anchor: 'bottom'
      });

      map.on("mousemove", "population-3d", (e) => {
        if (currentLayer !== "population") return;
        map.getCanvas().style.cursor = "pointer";

        const feature = e.features[0];
        const population = feature.properties.population ? feature.properties.population.toLocaleString() : "N/A";
        const name = feature.properties.NAME || "Unknown";

        popup.setLngLat(e.lngLat)
          .setHTML(\`<div><span class="popup-label">Location:</span> \${name}<br><span class="popup-label">Population:</span> \${population}</div>\`)
          .addTo(map);
      });

      map.on("mousemove", "income-3d", (e) => {
        if (currentLayer !== "income") return;
        map.getCanvas().style.cursor = "pointer";

        const feature = e.features[0];
        const income = feature.properties.income ? "$" + feature.properties.income.toLocaleString() : "N/A";
        const name = feature.properties.NAME || "Unknown";

        popup.setLngLat(e.lngLat)
          .setHTML(\`<div><span class="popup-label">Location:</span> \${name}<br><span class="popup-label">Median Income:</span> \${income}</div>\`)
          .addTo(map);
      });

      map.on("mouseleave", "population-3d", () => {
        map.getCanvas().style.cursor = "";
        popup.remove();
      });

      map.on("mouseleave", "income-3d", () => {
        map.getCanvas().style.cursor = "";
        popup.remove();
      });
    });

    // Toggle between population and income layers
    function showLayer(layerType) {
      if (layerType === "population") {
        map.setLayoutProperty("population-3d", "visibility", "visible");
        map.setLayoutProperty("income-3d", "visibility", "none");
        document.getElementById("btn-population").classList.add("active");
        document.getElementById("btn-income").classList.remove("active");
        document.getElementById("legend-title").textContent = "Population";
        document.getElementById("population-legend").style.display = "block";
        document.getElementById("income-legend").style.display = "none";
        currentLayer = "population";
      } else if (layerType === "income") {
        map.setLayoutProperty("population-3d", "visibility", "none");
        map.setLayoutProperty("income-3d", "visibility", "visible");
        document.getElementById("btn-population").classList.remove("active");
        document.getElementById("btn-income").classList.add("active");
        document.getElementById("legend-title").textContent = "Median Income";
        document.getElementById("population-legend").style.display = "none";
        document.getElementById("income-legend").style.display = "block";
        currentLayer = "income";
      }
    }

    // Toggle between 3D and 2D view
    function toggle3D(is3D) {
      if (is3D) {
        map.easeTo({
          pitch: 60,
          bearing: -17.6,
          duration: 1000
        });
        document.getElementById("btn-3d").classList.add("active");
        document.getElementById("btn-2d").classList.remove("active");
      } else {
        map.easeTo({
          pitch: 0,
          bearing: 0,
          duration: 1000
        });
        document.getElementById("btn-3d").classList.remove("active");
        document.getElementById("btn-2d").classList.add("active");
      }
    }
  </script>
</body>
</html>', pmtiles_file)

# 4. Serve using httpuv
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
    if (path == paste0("/", pmtiles_file)) {
      if (file.exists(pmtiles_file)) {
        file_size <- file.info(pmtiles_file)$size

        # Support HTTP Range requests for PMTiles
        range_header <- req$HTTP_RANGE

        if (!is.null(range_header) && grepl("^bytes=", range_header)) {
          # Parse Range: bytes=start-end
          range_parts <- sub("^bytes=", "", range_header)
          parts <- strsplit(range_parts, "-")[[1]]
          start <- as.numeric(parts[1])
          end <- if (parts[2] == "") file_size - 1 else as.numeric(parts[2])
          length <- end - start + 1

          # Read byte range
          con <- file(pmtiles_file, "rb")
          seek(con, start)
          data <- readBin(con, "raw", length)
          close(con)

          return(list(
            status = 206L,
            headers = list(
              "Content-Type" = "application/x-protobuf",
              "Content-Range" = sprintf("bytes %d-%d/%d", start, end, file_size),
              "Content-Length" = as.character(length),
              "Accept-Ranges" = "bytes",
              "Access-Control-Allow-Origin" = "*"
            ),
            body = data
          ))
        }

        # Serve full file
        return(list(
          status = 200L,
          headers = list(
            "Content-Type" = "application/x-protobuf",
            "Content-Length" = as.character(file_size),
            "Accept-Ranges" = "bytes",
            "Access-Control-Allow-Origin" = "*"
          ),
          body = readBin(pmtiles_file, "raw", file_size)
        ))
      } else {
        cat("ERROR: PMTiles file not found:", pmtiles_file, "\n")
        cat("Working directory:", getwd(), "\n")
        cat("Files in directory:", paste(list.files(), collapse=", "), "\n")
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
