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
