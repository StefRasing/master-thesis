#!/usr/bin/env bash
set -euo pipefail
root=${1:?}
task=${SLURM_ARRAY_TASK_ID:?}
if (( task <= 5 )); then
    domain=strings
    fold=$task
else
    domain=bitvectors
    fold=$((task - 5))
fi
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_NUM_PRECOMPILE_TASKS=1
depot=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/phalcon-domain.XXXXXX")
trap 'rm -rf -- "$depot"' EXIT
export JULIA_DEPOT_PATH="$depot:$HOME/.julia:"
julia="$HOME/phalcon-ablation-uncapped-20261112/bin/julia"
echo "Ranking $domain fold $fold on $(hostname)"
srun "$julia" --project="$root/master-thesis" --threads=1 --startup-file=no \
    "$root/master-thesis/experiments/run.jl" phalcon-domain-rank \
    "$domain" "$root/rankings" "$fold"
