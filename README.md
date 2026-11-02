# master-thesis
Master Thesis

Node output memory limits can be configured with `max_output_bytes` on
`GeneticIterator`, `phalcon` (for property synthesis), and `find_property!`, or as
a keyword on `LazyCostBasedBus`. Program synthesis defaults to 1 MiB; property
synthesis (`phalcon` and `find_property!`) defaults to 21 MiB. Pass `typemax(Int)`
to disable the limit.
After a node is evaluated, `Base.summarysize` measures its complete output vector,
including referenced values and counting shared objects once. Vectors exceeding
the limit are pruned; vectors exactly at the limit are accepted. Existing
`prune_node_by_output` callbacks remain available for other pruning criteria.
This bounds retained outputs per node, not allocation peaks or total search memory.

The string and ARC experiments use fixed budgets of 1 MiB for program outputs
and 21 MiB for property outputs, independent of input size. The property budget
allows approximately 1 MiB for each of 20 population members plus the target.
It remains fixed if the population size changes. Each limit covers the complete
output vector across all evaluated examples.

Search code is loaded through one module, which owns its dependencies and include
order:

```julia
include("src/PhalconModule.jl")
using .Phalcon
```

The exported API provides `GeneticIterator`, `LazyCostBasedBus`, `Property`,
`initialize!`, `find_solution`, `local_optimum_outputs`, `update_cost_function`,
`find_property!`, `phalcon`, `levenshtein`, and `hamming_distance`. Pass the DSL
module as `benchmark` and the training problem as `problem` when constructing a
`GeneticIterator`. Phalcon uses that iterator's DSL module for property evaluation.
For custom verbose output, pass `display_outputs` to `phalcon` (for example,
`display_outputs=benchmark.visualize` for ARC). The ARC property grammar remains
an experiment-specific adapter, outside the search module.

Run the regression tests with `julia --project=. test/runtests.jl`. The tests use
the dependencies pinned in `Manifest.toml`; no sibling checkout is required. CI instantiates that environment and runs the same entry point.

Experiments share `experiments/src/Experiments.jl`, with benchmark adapters for strings,
bitvectors, and ARC. Instantiate the environment once before running jobs:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
julia --project=. experiments/run.jl phalcon strings 1
julia --project=. experiments/run.jl heuristic arc 1 a
bash exe/submit.sh phalcon arc 5
bash exe/submit.sh phalcon strings 6 --mem=48G
```

Named experiment clients live in `experiments/presets/`; interactive examples
live in `experiments/playgrounds/`. See `experiments/README.md` for the layout.
Non-ARC heuristic runs perform five repetitions in a single output directory;
Phalcon runs and ARC shards perform one. ARC arrays map each run to four
100-problem shards (a–d). Array tasks have separate result files. The launcher
uses an already instantiated Julia depot, including any `JULIA_DEPOT_PATH` set
before submission. Slurm logs go to `exe/out`. Resource defaults preserve the
old settings and extra `sbatch` options can override them.

For custom experiments or playgrounds:

```julia
include("experiments/src/Experiments.jl")
using .Experiments
run_experiment(ExperimentConfig(
    algorithm=:phalcon, benchmark=:strings, store=false,
    task_names=["2171308"],
    iterator_options=(population_size=30,),
    phalcon_options=(property_stop_reduction_rate=0.5, timeout=60,),
))
```

`ExperimentConfig` also controls output path, repetitions, run label, ARC shard,
problem indices, and held-out example indices. Default splitting holds out the
first example. Benchmark adapters own selection filters, grammar choices, rule
costs, distance metrics, and property settings. Keyword overrides in
`iterator_options` and `phalcon_options` are passed to the shared algorithms.
Playgrounds use the same runner with storage disabled. The strings playground
explicitly retains its lower property cost budget of 2; production uses 3.

Property synthesis has one implementation. Its default stopping rule seeks the
largest admissible reduction (all but one local optimum); pass
`property_stop_reduction_rate=0.5` to `phalcon`, or
`stop_reduction_rate=0.5` to `find_property!`, for the former playground behavior.
The rate must be strictly between zero and one. Properties rejecting every local
optimum remain inadmissible in both modes.

Stored runs use version 3 records in `.runs/` directories. Resume matches exact
run identities, including configuration, seed, repetition, code and environment.
See `experiments/README.md` for the schema and legacy export.
