#!/usr/bin/env bash
set -euo pipefail
root=${1:?}
mode=${2:?}
domain=${3:-}
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
export JULIA_PKG_PRECOMPILE_AUTO=0 JULIA_NUM_PRECOMPILE_TASKS=1
depot=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/phalcon-batch.XXXXXX")
trap 'rm -rf -- "$depot"' EXIT
export JULIA_DEPOT_PATH="$depot:$HOME/.julia:"
julia="$HOME/phalcon-ablation-uncapped-20261112/bin/julia"
srun --label --kill-on-bad-exit=0 --ntasks="$SLURM_NTASKS" "$julia" \
    --project="$root/master-thesis" --threads=1 --startup-file=no "$root/run.jl" "$root" "$mode" "$domain"
