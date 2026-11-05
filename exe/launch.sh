#!/usr/bin/env bash
set -euo pipefail
algorithm=${1:?algorithm required}
benchmark=${2:?benchmark required}
batches=${3:?batch count required; use submit.sh}
batch_size=${4:?batch size required}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
index=${SLURM_ARRAY_TASK_ID:-1}
run=$(((index - 1) / batches + 1))
batch=$(((index - 1) % batches + 1))
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
srun julia --project="$root" --threads=1 --startup-file=no "$root/experiments/run.jl" \
    "$algorithm" "$benchmark" "$run" --batch "$batch" "$batch_size"
