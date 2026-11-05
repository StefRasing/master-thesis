# DAIC resource planning (2026-11-05)

## Scheduler settings

The DAIC environment is in transition. The [September update](https://daic.tudelft.nl/blog/2026/09/21/2026-09-21/)
says hardware moves in stages through early November. The submission script now defaults to `all` / `normal`; verify these against live limits.
The [new scheduler reference](https://doc.daic.tudelft.nl/docs/software/scheduler/)
specifies `--partition=all`, `--qos=normal`, and a required `--account`.
Find the account with `sacctmgr show user "$USER" withassoc format=account%20`.
The [old environment limits](https://daic.tudelft.nl/docs/manual/job-submission/priorities/)
were short=4 h, medium=36 h, long=7 days; these are NOT verified limits for the new environment.

Run `bash exe/inspect_cluster.sh > cluster-settings.txt` on the login node to
obtain live partition/QoS/account/array limits before submitting. No remote
access or account information was available during local profiling.

Use one node, one task, one CPU per task, no GPU. Search is serial and contains
no distributed or threaded search paths. Set `JULIA_NUM_THREADS=1`,
`OPENBLAS_NUM_THREADS=1`, `OMP_NUM_THREADS=1`; launch Julia with
`--threads=1 --startup-file=no`. Independent array jobs provide parallelism.
Keep the same Julia version, thread configuration and timing protocol across
algorithms. Instantiate/precompile once before running arrays. The manifest
uses sibling path dependencies `../HerbBenchmarks.jl` and `../HerbInterpret.jl`:
copy these checkouts too, at the same relative paths and revisions.

## Walltime accounting

The default search budget is 1,800 seconds **per fold per repetition**. Loading,
canonical warm-up, interpreter preparation, test evaluation and result I/O sit
outside that budget. Cancellation is cooperative: one DSL/compiler call can
overshoot. Therefore the following are budget totals, not hard runtime bounds
or predictions of expected completion time.

| Current job unit | Problems | Repetitions | Search budget total |
|---|---:|---:|---:|
| Phalcon strings | 124 | 1 | 224.5 h (449 folds) |
| Heuristic strings | 124 | 1 | 224.5 h (unsupported outputs skip search) |
| Phalcon bitvectors | 151 | 1 | 377.5 h (755 folds) |
| Heuristic bitvectors | 151 | 1 | 377.5 h (755 folds) |
| ARC, either algorithm, one shard | 100 | 1 | 50 h |

The table above describes whole suites and legacy 100-problem shards, not current
array tasks. `exe/submit.sh` now splits every domain into five-problem batches
per run. A batch has at most 25 folds (12.5 hours search), with an 18-hour default
walltime allowing 25% search headroom plus two hours, rounded up. ARC batches
have only five folds. `EXPERIMENT_BATCH_SIZE` changes the batch size and scales
the request conservatively. Override `--time` after compute-node measurement.
Account, QoS time limits, array limits and available memory still need live
verification. Submit `--test-only` first to validate scheduler acceptance.

Atomic per-fold results permit resuming unchanged configurations. Keep batch size
and source/environment unchanged when resubmitting; both affect identity.

## Reproducible resource pilots

`experiments/performance/resource_probe.jl` runs three evenly spaced suite
indices in a fresh process, seed 42, normal warm-up, interpreter reuse and all
normal folds. Each fold gets a short search deadline. This samples the suite;
it is not stratified by grammar, example size or observed difficulty and does
not establish a full-suite maximum. Each algorithm/domain has a separate peak
RSS measurement including imports, compilation and warm-up. Total allocated
bytes are allocation traffic, NOT required resident memory.

```sh
julia --project=. --threads=1 --startup-file=no \
  experiments/performance/resource_probe.jl phalcon arc 10 arc-pilot.json
```

Raw local pilot reports and logs are in `resource_results/`. Repeat pilots on
DAIC compute nodes (not the login node), then run selected difficult/largest
problems for the full 1,800-second budget and several consecutive tasks. This
checks longer-term population/property-bank growth and interpreter retention.
Use at least 1.5 times the largest observed full-budget peak RSS, rounded up to
GiB, as an initial memory request; increase if peaks continue to grow. Short
local pilots alone cannot justify reducing production memory safely.

Collect actual Slurm measurements including `.batch` and `srun` step rows:

```sh
sacct -j JOBID --units=G --format=JobID,State,Elapsed,Timelimit,AllocCPUS,TotalCPU,ReqMem,MaxRSS,ExitCode
seff JOBID
```

Use elapsed time including preparation to size walltime, and MaxRSS to size
`--mem`. Check failed/OOM/timed-out trials separately. Apple Silicon timings and
RSS do not directly predict Linux/x86 DAIC behavior.

## Local measurements

Julia 1.12.5, Apple M1, one Julia thread, 2026-11-05. Each row is a fresh
process with three problems, one repetition, and a 10-second budget per fold.
The string selection executed 13 folds; bitvectors and ARC executed three.
These historical bitvector pilots used the former fixed split. The probe now
uses five-fold bitvector evaluation (15 folds for three ten-example problems);
rerun it to measure the new workload and longer process lifetime.
Load + pilot includes module loading, warm-up, preparation, search and evaluation;
it excludes Julia process startup. Results are diagnostic (`store=false`).

| Domain | Algorithm | Peak RSS (GiB) | Load + pilot (s) | Initial DAIC pilot memory |
|---|---|---:|---:|---:|
| strings | Phalcon | 2.92 | 109.4 | 8G |
| strings | heuristic | 1.47 | 36.1 | 4G |
| bitvectors | Phalcon | 1.40 | 27.5 | 4G |
| bitvectors | heuristic | 1.29 | 16.0 | 4G |
| ARC | Phalcon | 2.15 | 69.5 | 8G |
| ARC | heuristic | 1.91 | 70.4 | 4G |

These memory values are requests for the next validation pilots, not certified
production settings. For example, submit a short probe on the new environment:

```sh
sbatch --account=YOUR_ACCOUNT --partition=all --qos=normal \
  --nodes=1 --ntasks=1 --cpus-per-task=1 --mem=8G --time=00:30:00 \
  --output=arc-pilot-%j.out --wrap='export JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1; srun julia --project=. --threads=1 --startup-file=no experiments/performance/resource_probe.jl phalcon arc 10 arc-pilot.json'
```

Submit from the repository root after preparing Julia and dependencies. Use a
unique output JSON path for each pilot. Check live QoS/partition limits first.
Production memory defaults remain conservative (32G, ARC 64G). Submission uses
smaller batches and `all` / `normal`; supply `--account` and verify live limits.
