# get the base image, the rocker/verse has R, RStudio and pandoc
FROM rocker/rstudio:4.3.1

# Get and install system dependencies
WORKDIR /home/rstudio/project

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
 	cmake \
 	gdal-bin \
 	libcurl4-openssl-dev \ 
 	libgdal-dev \
 	libicu-dev \
 	libjpeg-dev \
 	libnetcdf-dev \
 	libpng-dev \
 	libsecret-1-dev \
 	libsodium-dev \
 	libssl-dev \
 	libudunits2-dev \
 	libxml2-dev \
 	make \
 	pandoc \
 	cdo \
 && wget -q https://github.com/quarto-dev/quarto-cli/releases/download/v1.8.25/quarto-1.8.25-linux-amd64.deb \
 && apt install ./quarto-1.8.25-linux-amd64.deb \
 && rm -f ./quarto-1.8.25-linux-amd64.deb \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Get and install R packages to local library
COPY renv.lock renv.lock
COPY renv/activate.R renv/activate.R
COPY .Rprofile .Rprofile
RUN chown -R rstudio . \
  && sudo -u rstudio R -e 'renv::restore()' \
   && rm -rf /tmp/downloaded_packages /tmp/Rtmp*
 
RUN sudo -u rstudio quarto install tinytex

# Copy data to image
# COPY analysis/data analysis/data
