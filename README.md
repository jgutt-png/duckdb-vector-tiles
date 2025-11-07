# DuckDB Vector Tiles Demo

Interactive map displaying US Census block groups (242,000 polygons) using DuckDB's spatial functions and vector tiles.

## Features

- DuckDB 1.4+ with ST_AsMVT() for vector tile generation
- httpuv tile server serving tiles at runtime
- MapLibre/mapgl for interactive visualization
- All 242,000 US Census block groups

## Quick Start

### Docker (Recommended)

```bash
docker pull YOUR_USERNAME/duckdb-tiles:latest
docker run -p 8000:8000 YOUR_USERNAME/duckdb-tiles:latest
```

Then open your browser and the map will be served.

### Local Build

```bash
docker build -t duckdb-tiles .
docker run -p 8000:8000 duckdb-tiles
```

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
