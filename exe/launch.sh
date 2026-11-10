#!/usr/bin/env bash
set -euo pipefail
algorithm=${1:?algorithm required}
benchmark=${2:?benchmark required}
batches=${3:?batch count required; use submit.sh}
batch_size=${4:?batch size required}
first_run=${5:-1}
# Slurm executes a spool copy of this file, so submit.sh passes the checkout.
root=${6:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
index=${SLURM_ARRAY_TASK_ID:-1}
batch=$(((index - 1) % batches + 1))
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
if [[ ${EXPERIMENT_NODE_LOCAL_DEPOT:-0} == 1 ]]; then
    depot=$(mktemp -d "/tmp/thesis-julia-${SLURM_JOB_ID:-local}.XXXXXX")
    trap 'rm -rf -- "$depot"' EXIT
    export JULIA_DEPOT_PATH="$depot:$HOME/.julia:"
    export JULIA_NUM_PRECOMPILE_TASKS=1
fi
if [[ $algorithm == phalcon-ablation ]]; then
    run=$(((index - 1) / batches + 1))
    args=("$first_run" --batch "$batch" "$batch_size" --run "$run")
else
    run=$(((index - 1) / batches + first_run))
    args=("$run" --batch "$batch" "$batch_size")
fi
srun julia --project="$root" --threads=1 --startup-file=no "$root/experiments/run.jl" \
    "$algorithm" "$benchmark" "${args[@]}"
