#!/bin/bash

#PBS -P lo70
#PBS -q copyq
#PBS -l ncpus=1
#PBS -l mem=64GB
#PBS -l walltime=01:00:00
#PBS -l wd
#PBS -l jobfs=400GB

# Load module, always specify version number.
module load R/4.3.1

Rscript scripts/download_era5.R > logs/downlaod_era5.log