#!/usr/bin/env bash
# Submit from any directory; one array task per run and problem batch.
set -euo pipefail
algorithm=${1:?usage: submit.sh ALGORITHM BENCHMARK [RUNS] [sbatch options...]}
benchmark=${2:?benchmark required}
runs=${3:-5}
shift "$(( $# >= 3 ? 3 : $# ))"
[[ $algorithm == phalcon || $algorithm == heuristic ]] || { echo 'invalid algorithm' >&2; exit 2; }
[[ $benchmark == arc || $benchmark == strings || $benchmark == bitvectors ]] || { echo 'invalid benchmark' >&2; exit 2; }
[[ $runs =~ ^[1-9][0-9]*$ ]] || { echo 'RUNS must be positive' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$root/exe/out"
# Query the installed benchmark suite instead of assuming a fixed task count.
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
batch_size=${EXPERIMENT_BATCH_SIZE:-5}
[[ $batch_size =~ ^[1-9][0-9]*$ ]] || { echo 'EXPERIMENT_BATCH_SIZE must be positive' >&2; exit 2; }
count=$(julia --project="$root" --threads=1 --startup-file=no -e '
include(joinpath(ARGS[1], "experiments/src/Experiments.jl"))
using .Experiments
b = Symbol(ARGS[2])
print(length(Experiments.benchmark_tasks(ExperimentConfig(; benchmark=b), benchmark_adapter(b))))
' "$root" "$benchmark")
batches=$(((count + batch_size - 1) / batch_size))
tasks=$((runs * batches))
memory=32G
[[ $benchmark != arc ]] || memory=64G
# Five problems have at most 25 folds: 12.5h search plus preparation headroom.
hours=$(((batch_size * 25 + 7) / 8 + 2))
walltime="${hours}:00:00"
sbatch --partition="${SLURM_PARTITION:-all}" --qos="${SLURM_QOS:-normal}" --nodes=1 --ntasks=1 --cpus-per-task=1 \
    --mem="$memory" --time="$walltime" --array="1-$tasks" \
    --chdir="$root" --output="$root/exe/out/%A_%a.out" \
    --error="$root/exe/out/%A_%a.err" "$@" \
    "$root/exe/launch.sh" "$algorithm" "$benchmark" "$batches" "$batch_size"
