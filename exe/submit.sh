#!/usr/bin/env bash
# Submit from any directory; one array task per run and problem batch.
set -euo pipefail
algorithm=${1:?usage: submit.sh ALGORITHM BENCHMARK [RUNS or ABLATION_SETTING] [sbatch options...]}
benchmark=${2:?benchmark required}
selection=${3:-}
shift "$(( $# >= 3 ? 3 : $# ))"
[[ $algorithm == phalcon || $algorithm == heuristic || $algorithm == phalcon-ablation ]] || { echo 'invalid algorithm' >&2; exit 2; }
[[ $benchmark == arc || $benchmark == strings || $benchmark == bitvectors ]] || { echo 'invalid benchmark' >&2; exit 2; }
if [[ $algorithm == phalcon-ablation ]]; then
    selection=${selection:-all}
    [[ $selection == all || $selection =~ ^[1-9][0-9]*$ ]] || { echo 'ABLATION_SETTING must be a setting number or all' >&2; exit 2; }
    runs=1
    if [[ ${1:-} == --runs ]]; then
        runs=${2:?--runs requires a positive integer}
        shift 2
    fi
else
    runs=${selection:-5}
fi
[[ $runs =~ ^[1-9][0-9]*$ ]] || { echo 'RUNS must be positive' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$root/exe/out"
# Query the installed benchmark suite instead of assuming a fixed task count.
export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1
batch_size=${EXPERIMENT_BATCH_SIZE:-5}
[[ $batch_size =~ ^[1-9][0-9]*$ ]] || { echo 'EXPERIMENT_BATCH_SIZE must be positive' >&2; exit 2; }
suite=$(julia --project="$root" --threads=1 --startup-file=no -e '
include(joinpath(ARGS[1], "experiments/src/Experiments.jl"))
using .Experiments
b = Symbol(ARGS[2])
print(length(Experiments.benchmark_tasks(ExperimentConfig(; benchmark=b), benchmark_adapter(b))),
    " ", ARGS[3] == "phalcon-ablation" ? length(Experiments.ablation_settings()) : 0)
' "$root" "$benchmark" "$algorithm")
read -r count setting_count <<< "$suite"
batches=$(((count + batch_size - 1) / batch_size))
memory=32G
[[ $benchmark != arc ]] || memory=64G
folds_per_problem=5
minutes_per_fold=30
if [[ $algorithm == phalcon-ablation && $benchmark == arc ]]; then
    folds_per_problem=1
fi
# Allow 25% search headroom, round up to whole hours, then add two hours for preparation.
search_minutes=$((batch_size * folds_per_problem * minutes_per_fold))
hours=$(((search_minutes * 5 + 239) / 240 + 2))
walltime="${hours}:00:00"

submit_array() {
    local tasks=$1 first_run=$2
    shift 2
    sbatch --partition="${SLURM_PARTITION:-all}" --qos="${SLURM_QOS:-normal}" --nodes=1 --ntasks=1 --cpus-per-task=1 \
        --mem="$memory" --time="$walltime" --array="1-$tasks" \
        --chdir="$root" --output="$root/exe/out/%A_%a.out" \
        --error="$root/exe/out/%A_%a.err" "$@" \
        "$root/exe/launch.sh" "$algorithm" "$benchmark" "$batches" "$batch_size" "$first_run" "$root"
}

if [[ $algorithm == phalcon-ablation ]]; then
    # Each setting gets its own array to keep the array size independent of the grid size.
    first_setting=1
    last_setting=$setting_count
    if [[ $selection != all ]]; then
        [[ ${#selection} -le ${#setting_count} && $selection -le $setting_count ]] ||
            { echo "ABLATION_SETTING must be 1-$setting_count or all" >&2; exit 2; }
        first_setting=$selection
        last_setting=$selection
    fi
    for ((setting = first_setting; setting <= last_setting; setting++)); do
        submit_array "$((runs * batches))" "$setting" "$@"
    done
else
    submit_array "$((runs * batches))" 1 "$@"
fi
