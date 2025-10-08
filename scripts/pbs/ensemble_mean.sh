#!/bin/bash

#PBS -P lo70
#PBS -q normal
#PBS -l ncpus=48
#PBS -l mem=64GB
#PBS -l walltime=08:00:00
#PBS -l wd
#PBS -l jobfs=20GB
#PBS -o logs/
#PBS -e logs/
#PBS -l storage=gdata/ux62+scratch/k10+gdata/k10+gdata/ub7+gdata/rt52+gdata/dx2+gdata/lo70+gdata/hh5+gdata/lo07
#PBS -N ensemble_mean

# Load module, always specify version number.
module load R/4.3.1
module load cdo/2.4.3


# Run R application
SCRIPT=ensemble_mean.R
Rscript scripts/${SCRIPT} > logs/${SCRIPT}.log
