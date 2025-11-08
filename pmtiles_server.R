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

map_html <- '
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>US Population 3D Map</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <script src="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.js"></script>
  <link href="https://unpkg.com/maplibre-gl@3.6.2/dist/maplibre-gl.css" rel="stylesheet" />
  <script src="https://unpkg.com/pmtiles@2.11.0/dist/index.js"></script>
  <script src="https://unpkg.com/@turf/turf@6.5.0/turf.min.js"></script>
  <style>
    body { margin: 0; padding: 0; }
    #map { position: absolute; top: 0; bottom: 0; width: 100%; }
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
    #address-search {
      padding: 8px 12px;
      border: 1px solid #ccc;
      border-radius: 4px;
      font-size: 14px;
      width: 200px;
      margin-left: 5px;
      height: 34px;
      box-sizing: border-box;
    }
    #search-btn {
      padding: 8px 12px;
      background: #2171b5;
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 14px;
      height: 34px;
      box-sizing: border-box;
    }
    #search-btn:hover {
      background: #1a5a8f;
    }
    #stats-panel {
      position: absolute;
      top: 10px;
      right: 10px;
      background: white;
      padding: 15px;
      border-radius: 4px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.3);
      z-index: 10;
      font-family: Arial, sans-serif;
      font-size: 14px;
      max-width: 300px;
      display: none;
    }
    #stats-panel h3 {
      margin: 0 0 10px 0;
      font-size: 16px;
      border-bottom: 2px solid #2171b5;
      padding-bottom: 5px;
    }
    #stats-panel .stat-row {
      margin: 8px 0;
      display: flex;
      justify-content: space-between;
    }
    #stats-panel .stat-label {
      font-weight: bold;
      color: #555;
    }
    #stats-panel .stat-value {
      color: #2171b5;
      font-weight: bold;
    }
    #stats-panel .close-btn {
      position: absolute;
      top: 5px;
      right: 8px;
      cursor: pointer;
      font-size: 20px;
      color: #999;
      line-height: 1;
    }
    #stats-panel .close-btn:hover {
      color: #333;
    }
  </style>
</head>
<body>
  <div id="controls">
    <div>
      <button id="btn-population" class="active" onclick="showLayer(\'population\')">Population</button>
      <button id="btn-income" onclick="showLayer(\'income\')">Income</button>
      <input type="text" id="address-search" placeholder="Search address..." />
      <button id="search-btn" onclick="searchAddress()">Go</button>
    </div>
    <div style="margin-top: 10px;">
      <button id="btn-3d" class="active" onclick="toggle3D(true)">3D</button>
      <button id="btn-2d" onclick="toggle3D(false)">2D</button>
      <button id="btn-city-lines" onclick="toggleCityLines()">Roads</button>
      <button id="btn-pin" onclick="togglePinMode()">Pin</button>
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
  <div id="stats-panel">
    <span class="close-btn" onclick="closeStatsPanel()">&times;</span>
    <h3>3-Mile Radius Stats</h3>
    <div id="stats-content">
      <div class="stat-row">
        <span class="stat-label">Total Population:</span>
        <span class="stat-value" id="stat-population">-</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Avg Income:</span>
        <span class="stat-value" id="stat-income">-</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Block Groups:</span>
        <span class="stat-value" id="stat-blocks">-</span>
      </div>
      <div class="stat-row">
        <span class="stat-label">Area:</span>
        <span class="stat-value">3 mile radius</span>
      </div>
    </div>
  </div>
  <div id="map"></div>
  <script>
    let protocol = new pmtiles.Protocol();
    maplibregl.addProtocol("pmtiles", protocol.tile);

    // Track current layer for tooltips (global scope)
    let currentLayer = "population";
    let currentMarker = null;
    let pinModeActive = false;

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

      // Find the first symbol layer (for labels) to insert our layers before it
      const layers = map.getStyle().layers;
      let firstSymbolId;
      for (const layer of layers) {
        if (layer.type === \'symbol\') {
          firstSymbolId = layer.id;
          break;
        }
      }

      // Population layer (blue)
      map.addLayer({
        id: "population-3d",
        type: "fill-extrusion",
        source: "population",
        "source-layer": "population",
        paint: {
          "fill-extrusion-color": [
            "case",
            ["boolean", ["feature-state", "hover"], false],
            "#ffff00",  // Yellow highlight when hovering
            [
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
            ]
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
      }, firstSymbolId);

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
            "case",
            ["boolean", ["feature-state", "hover"], false],
            "#ffff00",  // Yellow highlight when hovering
            [
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
            ]
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
      }, firstSymbolId);

      map.addControl(new maplibregl.NavigationControl(), "top-right");

      // Add hover tooltip and highlight effect
      const popup = new maplibregl.Popup({
        closeButton: false,
        closeOnClick: false,
        anchor: "bottom"
      });

      let hoveredStateId = null;

      map.on("mousemove", "population-3d", (e) => {
        if (currentLayer !== "population") return;
        map.getCanvas().style.cursor = "pointer";

        if (e.features.length > 0) {
          if (hoveredStateId !== null) {
            map.setFeatureState(
              { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
              { hover: false }
            );
          }
          hoveredStateId = e.features[0].id;
          map.setFeatureState(
            { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
            { hover: true }
          );
        }

        const feature = e.features[0];
        const population = feature.properties.population ? feature.properties.population.toLocaleString() : "N/A";
        const name = feature.properties.NAME || "Unknown";

        popup.setLngLat(e.lngLat)
          .setHTML(\'<div><span class="popup-label">Location:</span> \' + name + \'<br><span class="popup-label">Population:</span> \' + population + \'</div>\')
          .addTo(map);
      });

      map.on("mousemove", "income-3d", (e) => {
        if (currentLayer !== "income") return;
        map.getCanvas().style.cursor = "pointer";

        if (e.features.length > 0) {
          if (hoveredStateId !== null) {
            map.setFeatureState(
              { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
              { hover: false }
            );
          }
          hoveredStateId = e.features[0].id;
          map.setFeatureState(
            { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
            { hover: true }
          );
        }

        const feature = e.features[0];
        const income = feature.properties.income ? "$" + feature.properties.income.toLocaleString() : "N/A";
        const name = feature.properties.NAME || "Unknown";

        popup.setLngLat(e.lngLat)
          .setHTML(\'<div><span class="popup-label">Location:</span> \' + name + \'<br><span class="popup-label">Median Income:</span> \' + income + \'</div>\')
          .addTo(map);
      });

      map.on("mouseleave", "population-3d", () => {
        if (hoveredStateId !== null) {
          map.setFeatureState(
            { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
            { hover: false }
          );
        }
        hoveredStateId = null;
        map.getCanvas().style.cursor = "";
        popup.remove();
      });

      map.on("mouseleave", "income-3d", () => {
        if (hoveredStateId !== null) {
          map.setFeatureState(
            { source: \'population\', sourceLayer: \'population\', id: hoveredStateId },
            { hover: false }
          );
        }
        hoveredStateId = null;
        map.getCanvas().style.cursor = "";
        popup.remove();
      });

      // Hide roads by default in 3D mode
      const styleLayers = map.getStyle().layers;
      styleLayers.forEach(layer => {
        if (layer.type === \'line\') {
          if (layer.id.includes(\'road\') || layer.id.includes(\'street\') ||
              layer.id.includes(\'highway\') || layer.id.includes(\'path\') ||
              layer.id.includes(\'tunnel\') || layer.id.includes(\'bridge\')) {
            map.setLayoutProperty(layer.id, \'visibility\', \'none\');
          }
        }
      });

      // Add sources for pin visualization
      map.addSource(\'pin-circle\', {
        type: \'geojson\',
        data: {
          type: \'Feature\',
          geometry: {
            type: \'Point\',
            coordinates: [0, 0]
          }
        }
      });

      map.addSource(\'pin-3d\', {
        type: \'geojson\',
        data: {
          type: \'Feature\',
          geometry: {
            type: \'Point\',
            coordinates: [0, 0]
          }
        }
      });

      // Add 3-mile radius circle layer (line for outline)
      map.addLayer({
        id: \'radius-circle-line\',
        type: \'line\',
        source: \'pin-circle\',
        paint: {
          \'line-color\': \'#FF3333\',
          \'line-width\': 5,
          \'line-opacity\': 1
        },
        layout: {
          \'visibility\': \'none\'
        }
      });

      // Add 3D elevated radius circle (fill-extrusion for 3D effect)
      map.addLayer({
        id: \'radius-circle-3d\',
        type: \'fill-extrusion\',
        source: \'pin-circle\',
        paint: {
          \'fill-extrusion-color\': \'#FF3333\',
          \'fill-extrusion-height\': 70000,
          \'fill-extrusion-base\': 0,
          \'fill-extrusion-opacity\': 0.4
        },
        layout: {
          \'visibility\': \'none\'
        }
      });

      // Add 3D pin marker (tall spike)
      map.addLayer({
        id: \'pin-3d-marker\',
        type: \'fill-extrusion\',
        source: \'pin-3d\',
        paint: {
          \'fill-extrusion-color\': [
            \'interpolate\',
            [\'linear\'],
            [\'get-height\'],
            0, \'#FF0000\',
            50000, \'#FF6666\',
            100000, \'#FF0000\'
          ],
          \'fill-extrusion-height\': 100000,
          \'fill-extrusion-base\': 0,
          \'fill-extrusion-opacity\': 0.95
        },
        layout: {
          \'visibility\': \'none\'
        }
      });

      // Add click handler for dropping pin and calculating stats
      map.on(\'click\', (e) => {
        // Only drop pin if pin mode is active
        if (!pinModeActive) return;

        // Don\'t add pin if clicking on controls
        if (e.originalEvent.target.closest(\'#controls\') ||
            e.originalEvent.target.closest(\'#legend\') ||
            e.originalEvent.target.closest(\'#stats-panel\')) {
          return;
        }

        // Remove existing marker if any
        if (currentMarker) {
          currentMarker.remove();
        }

        // Add new marker at clicked location - only show in 2D mode (when pitch is 0)
        const pitch = map.getPitch();
        if (pitch < 30) {
          currentMarker = new maplibregl.Marker({ color: \'#FF0000\' })
            .setLngLat(e.lngLat)
            .addTo(map);
        }

        // Calculate stats for 3-mile radius and get dynamic height
        const radiusHeight = calculateRadiusStats(e.lngLat);

        // Create and display 3-mile radius circle
        const radiusMiles = 3;
        const radiusKm = radiusMiles * 1.60934;
        const centerPoint = turf.point([e.lngLat.lng, e.lngLat.lat]);
        const circle = turf.circle(centerPoint, radiusKm, { units: \'kilometers\', steps: 64 });

        // Update circle source and show both line and 3D versions
        map.getSource(\'pin-circle\').setData(circle);
        map.setLayoutProperty(\'radius-circle-line\', \'visibility\', \'visible\');

        // Set dynamic height for 3D radius cylinder
        map.setPaintProperty(\'radius-circle-3d\', \'fill-extrusion-height\', radiusHeight);
        map.setLayoutProperty(\'radius-circle-3d\', \'visibility\', \'visible\');

        // Create 3D pin (small buffered point for tall spike) - make it taller than radius
        const pin3D = turf.buffer(centerPoint, 0.03, { units: \'kilometers\' });
        map.getSource(\'pin-3d\').setData(pin3D);
        map.setPaintProperty(\'pin-3d-marker\', \'fill-extrusion-height\', radiusHeight * 1.5);
        map.setLayoutProperty(\'pin-3d-marker\', \'visibility\', \'visible\');
      });
    });

    // Calculate statistics within 3-mile radius
    function calculateRadiusStats(center) {
      const radiusMiles = 3;
      const radiusKm = radiusMiles * 1.60934;

      // Create circle using turf
      const centerPoint = turf.point([center.lng, center.lat]);
      const circle = turf.circle(centerPoint, radiusKm, { units: \'kilometers\' });

      // Query features directly from source (not just rendered features)
      // This ensures we get all features regardless of zoom level or visibility
      const bbox = turf.bbox(circle);
      const features = map.querySourceFeatures(\'population\', {
        sourceLayer: \'population\',
        filter: [
          \'all\',
          [\'>=\', [\'get\', \'population\'], 0]
        ]
      });

      // Filter features within circle and aggregate stats
      let totalPopulation = 0;
      let totalIncome = 0;
      let blockCount = 0;
      let maxPopulation = 0;
      let maxIncome = 0;
      const seenIds = new Set();

      features.forEach(feature => {
        // Avoid counting same feature twice
        const featureId = feature.properties.GEOID || feature.id;
        if (seenIds.has(featureId)) return;
        seenIds.add(featureId);

        // Check if feature intersects or is within circle
        // Use turf.booleanIntersects for more accurate detection
        try {
          const featureGeom = feature.geometry || feature;
          const intersects = turf.booleanIntersects(circle, featureGeom);

          if (intersects) {
            const pop = parseInt(feature.properties.population) || 0;
            const inc = parseInt(feature.properties.income) || 0;

            totalPopulation += pop;
            if (inc > 0) {
              totalIncome += inc;
            }

            // Track max values for height calculation
            if (pop > maxPopulation) maxPopulation = pop;
            if (inc > maxIncome) maxIncome = inc;

            blockCount++;
          }
        } catch (e) {
          // If intersection check fails, fall back to center distance check
          const featureCenter = turf.center(feature);
          const distance = turf.distance(centerPoint, featureCenter, { units: \'kilometers\' });

          if (distance <= radiusKm) {
            const pop = parseInt(feature.properties.population) || 0;
            const inc = parseInt(feature.properties.income) || 0;

            totalPopulation += pop;
            if (inc > 0) {
              totalIncome += inc;
            }

            if (pop > maxPopulation) maxPopulation = pop;
            if (inc > maxIncome) maxIncome = inc;

            blockCount++;
          }
        }
      });

      // Calculate average income
      const avgIncome = blockCount > 0 ? Math.round(totalIncome / blockCount) : 0;

      // Calculate max height based on current layer
      // Population layer: 0-10000 pop -> 0-50000 height
      // Income layer: 0-200000 income -> 0-100000 height
      let maxHeight = 0;
      if (currentLayer === \'population\') {
        maxHeight = Math.min(maxPopulation / 10000 * 50000, 50000);
      } else {
        maxHeight = Math.min(maxIncome / 200000 * 100000, 100000);
      }

      // Make radius cylinder 20% taller than max block + minimum 5000m
      const radiusHeight = Math.max(maxHeight * 1.2, 5000);

      // Update stats panel
      document.getElementById(\'stat-population\').textContent = totalPopulation.toLocaleString();
      document.getElementById(\'stat-income\').textContent = avgIncome > 0 ? \'$\' + avgIncome.toLocaleString() : \'N/A\';
      document.getElementById(\'stat-blocks\').textContent = blockCount.toLocaleString();

      // Show stats panel
      document.getElementById(\'stats-panel\').style.display = \'block\';

      // Return the calculated radius height
      return radiusHeight;
    }

    // Close stats panel
    function closeStatsPanel() {
      document.getElementById(\'stats-panel\').style.display = \'none\';
      if (currentMarker) {
        currentMarker.remove();
        currentMarker = null;
      }
      // Hide all pin visualization layers
      map.setLayoutProperty(\'radius-circle-line\', \'visibility\', \'none\');
      map.setLayoutProperty(\'radius-circle-3d\', \'visibility\', \'none\');
      map.setLayoutProperty(\'pin-3d-marker\', \'visibility\', \'none\');
    }

    // Toggle pin mode
    function togglePinMode() {
      pinModeActive = !pinModeActive;

      if (pinModeActive) {
        document.getElementById("btn-pin").classList.add("active");
        map.getCanvas().style.cursor = \'crosshair\';
      } else {
        document.getElementById("btn-pin").classList.remove("active");
        map.getCanvas().style.cursor = \'\';
        // Close stats panel and remove pin when deactivating
        closeStatsPanel();
      }
    }

    // Add keyboard controls (WASD for panning, Q/E for rotation)
    // Camera-relative movement with smooth animation
    document.addEventListener(\'keydown\', (e) => {
      // Don\'t trigger if user is typing in search box
      if (e.target.tagName === \'INPUT\') return;

      const panAmount = 0.08; // degrees - amount to move per keypress
      const rotateAmount = 15; // degrees
      const center = map.getCenter();
      const bearing = map.getBearing();

      // Convert bearing to radians for trigonometry (bearing is clockwise from north)
      const bearingRad = (bearing * Math.PI) / 180;

      let deltaLng = 0;
      let deltaLat = 0;

      switch(e.key.toLowerCase()) {
        case \'w\':
          // Move forward in the direction camera is facing
          deltaLng = Math.sin(bearingRad) * panAmount;
          deltaLat = Math.cos(bearingRad) * panAmount;
          e.preventDefault();
          break;
        case \'s\':
          // Move backward (opposite of camera direction)
          deltaLng = -Math.sin(bearingRad) * panAmount;
          deltaLat = -Math.cos(bearingRad) * panAmount;
          e.preventDefault();
          break;
        case \'a\':
          // Move left (perpendicular to camera direction)
          deltaLng = -Math.cos(bearingRad) * panAmount;
          deltaLat = Math.sin(bearingRad) * panAmount;
          e.preventDefault();
          break;
        case \'d\':
          // Move right (perpendicular to camera direction)
          deltaLng = Math.cos(bearingRad) * panAmount;
          deltaLat = -Math.sin(bearingRad) * panAmount;
          e.preventDefault();
          break;
        case \'q\':
          // Rotate left
          map.easeTo({ bearing: bearing - rotateAmount, duration: 200 });
          e.preventDefault();
          break;
        case \'e\':
          // Rotate right
          map.easeTo({ bearing: bearing + rotateAmount, duration: 200 });
          e.preventDefault();
          break;
      }

      // Apply smooth camera-relative movement
      if (deltaLng !== 0 || deltaLat !== 0) {
        map.easeTo({
          center: [center.lng + deltaLng, center.lat + deltaLat],
          duration: 150,
          easing: (t) => t // linear easing for responsive feel
        });
      }
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
      const layers = map.getStyle().layers;

      if (is3D) {
        // 3D mode - restore extrusion heights and hide roads
        map.setPaintProperty("population-3d", "fill-extrusion-height", [
          "interpolate",
          ["linear"],
          ["get", "population"],
          0, 0,
          10000, 50000
        ]);
        map.setPaintProperty("income-3d", "fill-extrusion-height", [
          "interpolate",
          ["linear"],
          ["get", "income"],
          0, 0,
          200000, 100000
        ]);
        map.easeTo({
          pitch: 60,
          bearing: -17.6,
          duration: 1000
        });

        // Hide roads in 3D mode
        roadLinesVisible = false;
        layers.forEach(layer => {
          if (layer.type === \'line\') {
            if (layer.id.includes(\'road\') || layer.id.includes(\'street\') ||
                layer.id.includes(\'highway\') || layer.id.includes(\'path\') ||
                layer.id.includes(\'tunnel\') || layer.id.includes(\'bridge\')) {
              map.setLayoutProperty(layer.id, \'visibility\', \'none\');
            }
          }
        });
        document.getElementById("btn-city-lines").classList.remove("active");

        document.getElementById("btn-3d").classList.add("active");
        document.getElementById("btn-2d").classList.remove("active");
      } else {
        // 2D mode - flatten extrusion and show roads
        map.setPaintProperty("population-3d", "fill-extrusion-height", 0);
        map.setPaintProperty("income-3d", "fill-extrusion-height", 0);
        map.easeTo({
          pitch: 0,
          bearing: 0,
          duration: 1000
        });

        // Show roads in 2D mode
        roadLinesVisible = true;
        layers.forEach(layer => {
          if (layer.type === \'line\') {
            if (layer.id.includes(\'road\') || layer.id.includes(\'street\') ||
                layer.id.includes(\'highway\') || layer.id.includes(\'path\') ||
                layer.id.includes(\'tunnel\') || layer.id.includes(\'bridge\')) {
              map.setLayoutProperty(layer.id, \'visibility\', \'visible\');
            }
          }
        });
        document.getElementById("btn-city-lines").classList.add("active");

        document.getElementById("btn-3d").classList.remove("active");
        document.getElementById("btn-2d").classList.add("active");
      }
    }

    // Toggle road lines (start with roads hidden in 3D mode)
    let roadLinesVisible = false;
    function toggleCityLines() {
      roadLinesVisible = !roadLinesVisible;

      // Get all layers from the map style
      const layers = map.getStyle().layers;

      // Find and toggle visibility of road/street layers
      layers.forEach(layer => {
        // Hide all line layers that represent roads/streets
        if (layer.type === \'line\') {
          // Target road, street, highway, path layers
          if (layer.id.includes(\'road\') || layer.id.includes(\'street\') ||
              layer.id.includes(\'highway\') || layer.id.includes(\'path\') ||
              layer.id.includes(\'tunnel\') || layer.id.includes(\'bridge\')) {
            map.setLayoutProperty(
              layer.id,
              \'visibility\',
              roadLinesVisible ? \'visible\' : \'none\'
            );
          }
        }
      });

      // Update button state
      if (roadLinesVisible) {
        document.getElementById("btn-city-lines").classList.add("active");
      } else {
        document.getElementById("btn-city-lines").classList.remove("active");
      }
    }

    // Search for address using Nominatim API
    async function searchAddress() {
      const searchInput = document.getElementById("address-search");
      const address = searchInput.value.trim();

      if (!address) {
        alert("Please enter an address");
        return;
      }

      try {
        const response = await fetch(
          "https://nominatim.openstreetmap.org/search?format=json&q=" +
          encodeURIComponent(address) +
          "&countrycodes=us&limit=1"
        );
        const data = await response.json();

        if (data.length > 0) {
          const result = data[0];
          const lat = parseFloat(result.lat);
          const lon = parseFloat(result.lon);

          // Fly to the location
          map.flyTo({
            center: [lon, lat],
            zoom: 14,
            duration: 2000
          });

          // Add a temporary marker
          new maplibregl.Popup({ closeOnClick: true })
            .setLngLat([lon, lat])
            .setHTML(\'<div style="font-weight: bold;">\' + result.display_name + \'</div>\')
            .addTo(map);
        } else {
          alert("Address not found. Please try a different search.");
        }
      } catch (error) {
        console.error("Geocoding error:", error);
        alert("Error searching for address. Please try again.");
      }
    }

    // Allow Enter key to trigger search
    document.getElementById("address-search").addEventListener("keypress", function(event) {
      if (event.key === "Enter") {
        searchAddress();
      }
    });
  </script>
</body>
</html>'

# Replace %s with the pmtiles file name
map_html <- sub("%s", pmtiles_file, map_html, fixed = TRUE)

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
