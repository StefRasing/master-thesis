#!/usr/bin/env bash
set -euo pipefail
algorithm=${1:?algorithm required}
benchmark=${2:?benchmark required}
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
index=${SLURM_ARRAY_TASK_ID:-1}
args=("$algorithm" "$benchmark" "$index")
if [[ $benchmark == arc ]]; then
    shards=(a b c d)
    args=("$algorithm" "$benchmark" "$(((index - 1) / 4 + 1))" "${shards[$(((index - 1) % 4))]}")
fi
# Use a pre-instantiated depot. Set JULIA_DEPOT_PATH before submission if needed.
srun julia --project="$root" "$root/experiments/run.jl" "${args[@]}"
