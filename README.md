# access-s2_ice-eval

This repository contains data, code and other source files associated with Evaluating the Importance of Initial Conditions for Antarctic Sea Ice Seasonal Predictability with a Fully Coupled Model

First clone or download this repository with

```bash
git clone --depth 1 git@github.com:eliocamp/rcdo.git
```

## Requirements

1. [Quarto](https://quarto.org/).
2. R version 4.3.1. The easiest way to get it is using  [rig](https://github.com/r-lib/rig).
3. cdo. 
4. Other system dependencies: you can discover them by running `renv::sysreqs()`


## Installing R packages

This project uses the [renv](https://rstudio.github.io/renv/) package to manage a reproducible environment. If opening this project with RStudio or starting R from the command line from the root directory, renv should automagically install and load itself. 

To recreate the environment then run

```r
renv::restore()
```

This should install all the package dependencies needed to install the package and compile the document. Depending on your operating system, this could take a while!


## Compiling the manuscript

Render the document with 

```
quarto render analysis/paper/access-ice.qmd
```

At first run, this will download all necessary data, which is about 1.8Gb and can take a while. 

