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
    wget \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Go for go-pmtiles
RUN wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz && \
    rm go1.21.5.linux-amd64.tar.gz

ENV PATH="${PATH}:/usr/local/go/bin:/root/go/bin"

# Use RSPM for pre-built binaries on Ubuntu 24.04 (Noble)
ENV CRAN=https://packagemanager.posit.co/cran/__linux__/noble/latest

# Layer 1: Minimal dependencies (fastest, most stable)
RUN R -e "install.packages(c('sf', 'dplyr'), repos=Sys.getenv('CRAN'))" \
    && rm -rf /tmp/Rtmp*

# Layer 2: Census and visualization packages
RUN R -e "install.packages(c('tidycensus', 'mapgl', 'remotes'), repos=Sys.getenv('CRAN'))" \
    && rm -rf /tmp/Rtmp*

# Layer 3: PMTiles package from GitHub (installs go-pmtiles automatically)
RUN R -e "remotes::install_github('walkerke/pmtiles')" \
    && rm -rf /tmp/Rtmp*

# Set working directory
WORKDIR /app

# Copy the R script into the container
COPY pmtiles_server.R /app/

# Expose port for the tile server
EXPOSE 8000-8010

# Run the script
CMD ["Rscript", "pmtiles_server.R"]
