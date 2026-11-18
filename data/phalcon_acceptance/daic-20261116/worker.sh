#!/usr/bin/env bash
set -euo pipefail
root=${1:?}
mode=${2:?}
domain=${3:-}
baseline=$HOME/phalcon-ablation-uncapped-20261112
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 JULIA_PKG_PRECOMPILE_AUTO=0
depot=$(mktemp -d "${SLURM_TMPDIR:-/tmp}/phalcon-acceptance.XXXXXX")
trap 'rm -rf -- "$depot"' EXIT
export JULIA_DEPOT_PATH="$depot:$HOME/.julia:"
srun --label --ntasks="$SLURM_NTASKS" "$baseline/bin/julia" --project="$baseline/master-thesis" --threads=1 --startup-file=no "$root/run.jl" "$root" "$mode" "$domain"
