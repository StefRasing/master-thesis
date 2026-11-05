#!/usr/bin/env bash
# Submit from any directory; one array task per run (and per ARC shard).
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
tasks=$runs
memory=32G
walltime=72:00:00
if [[ $benchmark == arc ]]; then
    tasks=$((runs * 4))
    memory=64G
    walltime=168:00:00
elif [[ $algorithm == heuristic ]]; then
    walltime=24:00:00
fi
sbatch --partition=general --qos=long --ntasks=1 --cpus-per-task=1 \
    --mem="$memory" --time="$walltime" --array="1-$tasks" \
    --chdir="$root" --output="$root/exe/out/%A_%a.out" \
    --error="$root/exe/out/%A_%a.err" "$@" \
    "$root/exe/launch.sh" "$algorithm" "$benchmark"
