#!/bin/bash

#SBATCH --partition=general   # Request partition. Default is 'general'. Select the best partition following the advice on  https://daic.tudelft.nl/docs/manual/job-submission/priorities/#priority-tiers
#SBATCH --qos=medium          # Request Quality of Service. Default is 'short' (maximum run time: 4 hours)
#SBATCH --time=10:00:00       # Request run time (wall-clock). Default is 1 minute
#SBATCH --ntasks=1            # Request number of parallel tasks per job. Default is 1
#SBATCH --cpus-per-task=8     # Request number of CPUs (threads) per task. Default is 1 (note: CPUs are always allocated to jobs per 2).
#SBATCH --mem=8GB             # Request memory (MB) per node. Default is 1024MB (1GB). For multiple tasks, specify --mem-per-cpu instead
#SBATCH --output=strings_limited_increase_0.7_phalcon_%j.out # Set name of output log. %j is the Slurm jobId
#SBATCH --error=strings_limited_increase_0.7_phalcon_%j.err  # Set name of error log. %j is the Slurm jobId

export JULIA_DEPOT_PATH=$TMPDIR/julia_depot
mkdir -p $JULIA_DEPOT_PATH

srun julia --project=master-thesis -e 'include("experiments/strings/limited_increase/phalcon.jl")' 0.7