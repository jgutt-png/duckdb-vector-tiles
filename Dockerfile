FROM rocker/r-ver:latest

# Install system dependencies efficiently (single layer, no recommends)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libudunits2-dev \
    libgdal-dev \
    libgeos-dev \
    libproj-dev \
    cmake \
    libabsl-dev \
    xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Use RSPM for pre-built binaries on Ubuntu 22.04 (Jammy)
ENV CRAN=https://packagemanager.posit.co/cran/__linux__/jammy/latest

# Layer 1: Minimal dependencies (fastest, most stable)
RUN R -e "install.packages(c('DBI', 'httpuv'), repos=Sys.getenv('CRAN'))" \
    && rm -rf /tmp/Rtmp*

# Layer 2: Lightweight packages
RUN R -e "install.packages(c('tigris', 'mapgl'), repos=Sys.getenv('CRAN'))" \
    && rm -rf /tmp/Rtmp*

# Layer 3: Spatial packages (moderate compilation)
RUN R -e "install.packages(c('sf', 'duckspatial'), repos=Sys.getenv('CRAN'))" \
    && rm -rf /tmp/Rtmp*

# Layer 4: duckdb (heaviest - separate layer for caching)
# Reduce to 4 cores to avoid exhausting Docker resources
RUN R -e "install.packages('duckdb', repos=Sys.getenv('CRAN'), Ncpus=4)" \
    && rm -rf /tmp/Rtmp*

# Set working directory
WORKDIR /app

# Expose port range for the tile server
EXPOSE 8000-8010

# Run the script
CMD ["Rscript", "duckdb_vector_tiles.R"]
