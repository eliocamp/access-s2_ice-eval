# Evaluating the Importance of Initial Conditions for Antarctic Sea Ice Seasonal Predictability with a Fully Coupled Model

This repository contains data, code and other source files associated with Evaluating the Importance of Initial Conditions for Antarctic Sea Ice Seasonal Predictability with a Fully Coupled Model

First clone or download this repository with

```bash
git clone --depth 1 git@github.com:eliocamp/rcdo.git
```

## Runing with docker

The easiest way to run this code is to use the docker environment, which comes with all the packages and system dependencies preinstalled. 

[Install Docker](https://docs.docker.com/engine/install/) if you haven't already. Then, go to the folder in which you cloned the repository and run this line:

```
docker run --rm -p 8787:8787 -e DISABLE_AUTH=true -v $(pwd):/home/rstudio/project -v /home/rstudio/project/renv -v /home/rstudio/project/analysis/data eliocamp/access-s2_ice
```

Open your web browser to [localhost:8787](http://127.0.0.1:8787/) and you'll be welcomed by an RStudio session with a project folder with all that you need. And you can move [to the next section](#compiling-the-manuscript).


## Running locally

If you can't or don't want to use Docker, then you need to install all the requires packages. 


1. [Quarto](https://quarto.org/) (version 1.8 was used )

2. R version 4.3.1. The easiest way to get it is using  [rig](https://github.com/r-lib/rig).

3. cdo. 

4. Other system dependencies. On Ubuntu these should suffice: 

  ```bash
  sudo apt install cmake gdal-bin libcurl4-openssl-dev libgdal-dev libicu-dev libjpeg-dev libnetcdf-dev libpng-dev libsecret-1-dev libsodium-dev libssl-dev libudunits2-dev libxml2-dev make pandoc cdo
  ```

  you can discover them with R by running `renv::sysreqs(local = TRUE, collapse = TRUE)` from the project directory. 

## Installing R packages

This project uses the [renv](https://rstudio.github.io/renv/) package to manage a reproducible environment. If opening this project with RStudio or starting R from the command line from the root directory, renv should automagically install and load itself. 

To recreate the environment then run

```r
renv::restore()
```

Depending on your operating system, this could take a while!


## Compiling the manuscript

Render the document with 

```bash
quarto render analysis/paper/access-ice.qmd
```

At first run, this will download all necessary data, which is about 1.8Gb and can take a while. 

