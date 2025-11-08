# US Census Population & Income 3D Visualization

Interactive 3D map showing US Census data (242k block groups) with population and median income visualizations using PMTiles.

## Features

- **3D/2D Toggle**: Switch between 3D extrusion and flat 2D views
- **Dual Layers**: Toggle between Population (blue) and Income (green/yellow) visualizations
- **Hover Tooltips**: See actual numbers and location names on hover
- **Address Search**: Search any US address and fly to location
- **Color-Coded Legend**: Visual scale for data values
- **Persistent Caching**: 603 MB PMTiles file cached to avoid re-downloading Census data

## Local Development (Fast!)

### First Time Setup

```bash
# Build the Docker image (takes ~5 min)
docker-compose build

# Start the server
docker-compose up
```

Visit **http://localhost:8080**

**First run will take 10-15 minutes** to download Census data for all 50 states + DC + PR.
**Subsequent runs start instantly** thanks to persistent volume caching!

### Quick Development Workflow

```bash
# Start server in background
docker-compose up -d

# View logs
docker-compose logs -f

# Make changes to pmtiles_server.R, then restart:
docker-compose restart

# Stop server
docker-compose down
```

**Note**: Code changes require container restart to take effect!

## Cloud Deployment

### Google Cloud Run

```bash
gcloud run deploy duckdb-tiles \
  --source . \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 4Gi \
  --cpu 4
```

### Railway

```bash
railway init
railway up
```

## Architecture

- **rocker/r-ver**: Base R image (Ubuntu 24.04)
- **RSPM**: Pre-built R package binaries for fast installation
- **DuckDB**: In-process analytics database with spatial extension
- **httpuv**: R web server for tile endpoints
- **sf/tigris**: Spatial data handling and Census data access

## Build Optimizations

The Dockerfile uses 4 optimized layers:
1. System dependencies (GDAL, GEOS, PROJ)
2. Minimal R packages (DBI, httpuv)
3. Lightweight packages (tigris, mapgl)
4. Spatial packages (sf, duckspatial)
5. DuckDB (isolated for caching)

## Credits

Based on [Kyle Walker's gist](https://gist.github.com/walkerke/c90ab6b8f403169e615eabeb0339b15b) demonstrating DuckDB vector tiles with R.
