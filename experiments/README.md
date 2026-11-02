# Experiments

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
Search algorithms remain in the repository's root `src/`; benchmark-specific
experiment code belongs here. Slurm submission lives in `exe/submit.sh` and
continues to call `experiments/run.jl`. Results remain under the root `data/`.

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
