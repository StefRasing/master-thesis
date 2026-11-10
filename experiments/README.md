# Experiments

For DAIC scheduler settings, budget accounting and reproducible memory pilots,
see [Slurm resource planning](performance/SLURM_RESOURCES.md).

Run commands from the repository root. Activate and instantiate the root Julia
project before running experiments (see the repository README).

```text
experiments/
├── run.jl                   # Single command-line entry point
├── presets/                 # Named algorithm/benchmark clients
├── playgrounds/             # Small exploratory clients; storage disabled
└── src/
    ├── Experiments.jl       # Module entry point and imports
    ├── config.jl            # Explicit experiment configuration
    ├── benchmarks.jl        # Benchmark selection and algorithm defaults
    ├── arc_property_grammar.jl
    ├── runner.jl            # Splitting, synthesis, evaluation, repetition
    ├── io.jl                # Result storage and resume counts
    └── cli.jl               # Command-line argument handling
```

```sh
julia --project=. experiments/run.jl phalcon strings 1
julia --project=. experiments/run.jl heuristic arc 1 a
julia --project=. experiments/presets/phalcon_arc.jl 1 a
julia --project=. experiments/playgrounds/phalcon_strings.jl
```

The former top-level named scripts have moved to `presets/`. Playground filenames
no longer need the `_playground` suffix because their directory identifies them.
The shared module is loaded with `include("experiments/src/Experiments.jl")`.
Set `ExperimentConfig(verbose=true, ...)` to print Phalcon's search diagnostics.
It defaults to `false`; an explicit `phalcon_options.verbose` takes precedence.
Search algorithms remain in the repository's root `src/`; benchmark-specific
experiment code belongs here. Slurm submission lives in `exe/submit.sh` and
continues to call `experiments/run.jl`. Results remain under the root `data/`.

Slurm arrays run one attempt per fold, in batches of five problems per run.
`bash exe/submit.sh heuristic strings 5 --account=YOUR_ACCOUNT` submits five
independent runs split into batches (25 batches for strings, 31 for bitvectors,
80 for ARC with the current suite). Defaults are partition `all`, QoS `normal`;
verify live cluster limits with `exe/inspect_cluster.sh`. Override via sbatch
options or `SLURM_PARTITION` / `SLURM_QOS`. `EXPERIMENT_BATCH_SIZE` changes the
batch size; walltime scales with the maximum five folds plus overhead headroom.
This is a cooperative budget estimate, not a hard completion guarantee.
All workers use one Julia/BLAS/OpenMP thread and disable startup files.
Results share each run's directory and are atomically stored per fold. Keep batch
size unchanged when resuming because selection is part of the result identity.
The CLI also accepts `ALGORITHM BENCHMARK RUN --batch INDEX SIZE`.
Direct CLI/preset calls keep their existing full-suite or ARC-shard selection.

For a temporary diagnostic pass over **every problem and fold in all six
algorithm/domain combinations**, run:

```sh
julia --project=. --threads=1 --startup-file=no experiments/preflight.jl data/preflight/my-check 0.05
```

It stores real v3 archives, flat metric exports and `summary.json` in the selected
directory. The tiny per-fold search budget checks loading, splits, interpreter
preparation, timeout handling, storage and resume identities. These are diagnostic
outcomes, not production accuracy measurements or full-budget memory tests.
Keep the directory to inspect JSON fields; it is excluded from Git.

Earlier heuristic strings/bitvectors clients stored five repetitions together in
`data/heuristic_strings_20.runs` or `data/heuristic_bitvectors_20.runs`. Those
archives remain readable but are not resumed by the new run-specific layout.
Run IDs and repetition indices enter the RNG seed and result identity, so the
new five-run layout does not reproduce the old five-repetition random streams.

## Reproducible result format (version 3)

Stored experiments use this layout:

```text
experiment.runs/
  provenance/<hash>.json
  results/<problem>__rep-<repetition>__seed-<seed>__<run_id>.json
```

Results contain schema version, identity (problem, configuration, seed,
repetition and provenance hash), RNG name, timestamps, and trial metrics.
They never embed provenance or source contents. One atomic provenance snapshot
is shared across all problems and repetitions using the same code/environment.
It contains Git revision, relevant uncommitted patch, per-file source hashes,
Julia version, platform, thread count, preferences, and exact Project/Manifest
text. New snapshots do not contain full source copies. Commit source changes
before thesis runs; a patch cannot reconstruct untracked files from hashes.

Each trial uses its own Xoshiro RNG. Resume checks the full identity, including
configuration and code/environment hash. Increasing repetitions schedules only
missing trials. Set the base seed using `ExperimentConfig(seed=42, ...)`.
Instantiate/precompile once before submitting jobs. Conservative compatibility
bounds and the retained manifest preserve the dependency environment.

Snapshots and results are atomically published without overwriting concurrent
winners, using same-filesystem hard links. Duplicate workers may compute twice.
Incomplete temporary files are ignored. This protects against interrupted
processes, not power loss; the filesystem must support atomic hard links.
Timing-based stopping can still differ across machines.

`Experiments.load_results(path)` supports both old and new directories and legacy
JSON arrays. `Experiments.export_legacy(path, destination)` exports flat metrics
for existing analysis. Older hash-only filenames remain readable.

To compact old embedded v2 records:

```julia
Experiments.compact_results!("data/phalcon_strings/phalcon_strings1.runs")
```

This preserves run identities and metrics, saves original provenance once,
publishes compact v3 results, then removes the old redundant files. Re-running
is safe. Historical provenance retains its original source snapshots; new
snapshots store only source hashes and patches. Keep provenance alongside results.
Function-valued stored configuration overrides are rejected; put such behavior
in versioned adapter code instead.

Playground clients may be included repeatedly in the same REPL. They reuse the
loaded `Experiments` module and qualify API calls to avoid stale or ambiguous
exports. Restart Julia after changing implementation files to load the new code.
With storage disabled, the runner skips provenance collection and returns plain
trial results. It prints training/test status, elapsed time, evaluation count,
and solution per trial, followed by totals. Playground clients keep these plain
results in `playground_results` and return `nothing` to avoid a REPL data dump.
All playgrounds use `store=false`; stored experiment runs retain archival metadata.

## Comparison settings

Both algorithms default to 10 generations without improvement and a shared
`ExperimentConfig(timeout=1800)` budget in seconds per trial. The cooperative
deadline covers initialization and search; Phalcon also includes property
invention. Individual DSL/interpreter calls cannot be interrupted, so this is
not a hard execution limit. `iterator_options` can override the stagnation
setting, and existing `phalcon_options.timeout` overrides still take precedence
for Phalcon. Effective settings are saved with supported trials.

The heuristic string baseline cannot handle non-string outputs. These tasks
remain in the benchmark denominator and are recorded as unsolved with zero
search work; Phalcon attempts them. This intentionally measures that baseline
limitation. Historical runs using four stagnant generations or no baseline
deadline must be rerun to use the matched defaults.

## Phalcon ablation

The ablation crosses population sizes 10, 20, 50 and 100 with maximum property
costs 1, 2, 3 and 4. It uses one repetition and a 30-minute search budget per
fold. The population size also sets the GP population size. Other search
settings use the usual Phalcon defaults. Each problem and fold starts with the
same RNG seed across settings, and evaluation uses the standard domain splits.

Run all 16 settings for a domain locally or submit them as one Slurm array per
setting. Each command below covers strings, bitvectors and the full ARC suite.

```sh
for domain in strings bitvectors arc; do
    julia --project=. --threads=1 --startup-file=no experiments/run.jl phalcon-ablation "$domain"
done

for domain in strings bitvectors arc; do
    bash exe/submit.sh phalcon-ablation "$domain" all --account=YOUR_ACCOUNT
done
```

Setting IDs 1–4 use population 10, 5–8 use 20, 9–12 use 50, and 13–16 use 100.
Within each group, costs run from 1 to 4. For example, setting 10 uses population
50 and cost 2. Append `10` after the domain for a single setting locally, or
replace `all` with `10` for Slurm. Local runs for one setting also accept
`--batch INDEX SIZE` after the setting ID.

Set `PHALCON_ABLATION_POPULATIONS=10,20,40,80` to select a different population
grid with the same four property costs. Pass `--runs 5` immediately after the
Slurm setting selection to schedule five independent runs per setting. Run IDs
match across settings so that each problem and fold uses paired RNG seeds.

Results are stored in `data/phalcon_ablation/<domain>/pop-<size>_cost-<cost>.runs`.
Repeat the same command with the same batch size and source/environment to resume.
Use a consistent batch layout per setting so a fold has one result identity.

## Timing protocol and interpreter reuse

The runner uses `timing_protocol=:warmed_v1`. On every invocation, including
resume, it runs an untimed, fixed synthetic workload for both algorithms, followed
by property enumeration on canonical benchmark representatives (one per output
type). The representatives do not depend on task selection, order, shard or seed.
Warm-up RNGs and search state are discarded. This is representative warm-up,
not a guarantee that Julia will never compile another specialization.

Before a supported trial's budget starts, the runner constructs and exercises its
grammar's output interpreter using bounded extension initialization. This scratch
initialization's outputs, population and counters are discarded. The measured
trial still performs its own initialization, using its independently seeded RNG.
The interpreter contains no cached problem outputs or search state.

`reuse_interpreter=true` retains prepared output interpreters for identical grammar
objects within one invocation. `false` prepares a new interpreter before each
trial; both settings exclude output-interpreter preparation from measurement.
Resuming repeats warm-up and prepares interpreters before remaining trials.
Property grammars, property interpreters and property search created by Phalcon
remain inside the measured budget. Within one Phalcon run, property enumeration
reuses its output interpreter for the unchanged property grammar and benchmark
module. It is created lazily during the first property search; its construction
and any compilation stay inside that search's budget. Inputs, candidate outputs,
enumeration banks and counters are rebuilt or updated per search as before; no
property-search state or interpreter is retained across Phalcon runs. Test-set
evaluation remains outside it.
The common configured timeout includes search initialization and search; cancellation
is cooperative and can overshoot during an individual DSL or compiler call.

The protocol is included in archived configuration identities, so old timing
results cannot be silently resumed as warmed results. Rerun earlier experiments
for the paper's main comparison. Before the full suite, check representative
seeded trials across fresh processes, task orders and resume boundaries for
material residual compilation effects. Use identically warmed isolated processes
per trial if those effects remain material.

Adapter grammars must remain unchanged during a run. Property grammars are deep
copies and do not share the prepared output interpreter. Equal but separately
constructed grammars are deliberately not deduplicated.

## Enumeration counts

`programs_enumerated` counts candidates interpreted during initialization
(including intermediate types, rejected outputs, and observational duplicates),
plus genetic candidates submitted to the population, including rejected candidates.
Initialization candidates are counted once; rebuilding the population from cached
extensions after a cost update adds no counts.

`properties_enumerated` counts candidates interpreted during property enumeration,
including intermediate subprograms and candidates later pruned or deduplicated.
It accumulates across property searches, including work before a timeout, and is
zero for the heuristic baseline and trials that do not invent properties.
Both counts are saved and displayed. They count candidates, not per-example
interpreter calls; property-based cost evaluation and cached rescoring are excluded.
They therefore do not measure total synthesis work or sample efficiency. Historical
results retain their original counts and must be rerun to use these semantics.

## Evaluation splits

Strings and bitvectors use reproducibly shuffled, balanced 5-fold cross-validation. Problems
with fewer than five examples use leave-one-out evaluation (`k = min(5, n)`).
Every example is held out exactly once per repetition. The partition depends
only on the base seed and problem name, so algorithms, runs and repetitions
share the same folds. Each fold starts a fresh search with its own RNG and full
per-trial timeout; cross-validation multiplies the search budget by `k`.

ARC uses the official HerbBenchmarks training/test split metadata, holding out
all official test examples, including tasks with multiple test examples. Missing
or inconsistent metadata raises an error rather than inferring a split. There is
no inner cross-validation. Historical ARC runs that held out only the final
example must be rerun for the official protocol. Bitvectors now use the same
five-fold protocol as strings: current ten-example tasks train on eight examples
and test on two per fold. Earlier first-example-only bitvector results must be
rerun for this protocol. An explicit `ExperimentConfig(test_indices=[...])`
overrides the default protocol with one fixed split for any domain. Problems
need at least two examples.

Each fold is a separate result with `fold`, `folds`, `train_test_split`,
`test_examples`, and `correct_test_examples`. Fold and held-out indices are part
of the stored identity, so resume handles folds independently. Repetitions remain
independent synthesis attempts, not additional folds. To aggregate accuracy,
sum correct and held-out example counts within each problem/repetition, divide,
then average across repetitions and problems. This gives each problem equal
weight even when fold sizes or example counts differ. `solved_test_examples`
continues to indicate whether every example in that fold was solved.
