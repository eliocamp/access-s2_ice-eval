#!/bin/bash

#PBS -P gb02
#PBS -q normal
#PBS -l ncpus=48
#PBS -l mem=64GB
#PBS -l walltime=12:00:00
#PBS -l wd
#PBS -l jobfs=400GB
#PBS -o logs/
#PBS -e logs/
#PBS -l storage=gdata/ux62+scratch/k10+gdata/k10+gdata/ub7+gdata/rt52+gdata/dx2+gdata/lo70+gdata/hh5+gdata/lo70+scratch/lo70
#PBS -N build_ensemble3

# Load module, always specify version number.
module load R/4.3.1
module load cdo/2.4.3

# Must include `#PBS -l storage=scratch/ab12+gdata/yz98` if the job
# needs access to `/scratch/ab12/` and `/g/data/yz98/`. Details on:
# https://opus.nci.org.au/display/Help/PBS+Directives+Explained

# Run R application
export CHUNK=3
Rscript scripts/build_ensemble.R > logs/build_ensemble3.log
