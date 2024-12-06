#!/bin/bash

#PBS -P lo70
#PBS -q normal
#PBS -l ncpus=48
#PBS -l mem=128GB
#PBS -l walltime=1:00:00
#PBS -l wd
#PBS -l jobfs=400GB
#PBS -l storage=gdata/ux62+scratch/k10+gdata/ub7+gdata/rt52+gdata/dx2+gdata/lo70+gdata/hh5

# Load module, always specify version number.
module load R/4.3.1
module load cdo/2.4.3

# Must include `#PBS -l storage=scratch/ab12+gdata/yz98` if the job
# needs access to `/scratch/ab12/` and `/g/data/yz98/`. Details on:
# https://opus.nci.org.au/display/Help/PBS+Directives+Explained

# Run R application
export PBS_WORKERS=48
Rscript scripts/error_metrics.R 
