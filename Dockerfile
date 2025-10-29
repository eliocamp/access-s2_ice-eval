# get the base image, the rocker/verse has R, RStudio and pandoc
FROM rocker/rstudio:4.3.1

# Get and install system dependencies
WORKDIR /home/rstudio/project

RUN apt update \
 && apt install -y cmake gdal-bin libcurl4-openssl-dev libgdal-dev libicu-dev libjpeg-dev libnetcdf-dev libpng-dev libsecret-1-dev libsodium-dev libssl-dev libudunits2-dev libxml2-dev make pandoc cdo && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.8.25/quarto-1.8.25-linux-amd64.deb \
  && apt install ./quarto-1.8.25-linux-amd64.deb 

# Get and install R packages to local library
COPY renv.lock renv.lock
COPY renv/activate.R renv/activate.R
COPY .Rprofile .Rprofile
RUN chown -R rstudio . \
  && sudo -u rstudio R -e 'renv::restore()'
 
RUN sudo -u rstudio quarto install tinytex

# Copy data to image
# COPY analysis/data analysis/data
