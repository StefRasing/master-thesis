# master-thesis
Master Thesis

Node output memory limits can be configured with `max_output_bytes` on
`GeneticIterator`, `phalcon` (for property synthesis), and `find_property!`, or as
a keyword on `LazyCostBasedBus`. Program synthesis defaults to 1 MiB; property
synthesis (`phalcon` and `find_property!`) defaults to 21 MiB. Pass `typemax(Int)`
to disable the limit.
After a node is evaluated, its complete output vector is checked against the
`Base.summarysize` limit, including referenced values and counting shared objects
once. On Julia 1.12, strings, pointer-free values and nested dense arrays use a
conservative fast acceptance bound that includes backing capacity. Unknown values
and inconclusive bounds fall back to `Base.summarysize`; overestimates never
reject outputs. Other Julia versions use the general traversal. Vectors exceeding
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
the dependencies pinned in `Manifest.toml`. This development environment links
`HerbInterpret` to `../HerbInterpret.jl`, which contains the rule-local compiler
change; keep that sibling checkout available when instantiating or running jobs.
Before using a standalone checkout in CI or on a cluster, publish the HerbInterpret
change and replace the local path with its pinned revision.

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
    phalcon_options=(timeout=60,),
))
```

`ExperimentConfig` also controls output path, repetitions, run label, ARC shard,
problem indices, and held-out example indices. Default splitting holds out the
first example. Benchmark adapters own selection filters, grammar choices, rule
costs, distance metrics, and property settings. Keyword overrides in
`iterator_options` and `phalcon_options` are passed to the shared algorithms.
Playgrounds use the same runner. Set
`phalcon_options=(max_property_evaluations=10_000,)` to configure the
per-search evaluation budget, which defaults to 10,000.

`agreement` counts the local optima whose property outputs match the target on
every example. Phalcon defaults to `agreement_threshold=1`. The agreement
threshold variant, **Phalcon-AT**, uses a larger threshold. For Phalcon-AT(5),
pass `agreement_threshold=5` to `phalcon` or `find_property!`, or use
`phalcon_options=(agreement_threshold=5,)` in `ExperimentConfig`. The search
stops at the first property with agreement from 1 through the threshold,
inclusive. If it exhausts the evaluation budget first, it returns the property with
the lowest positive agreement found, or `nothing` if none had positive
agreement. The `heuristic` statistics store the agreement alongside each
selected property.

Stored runs use version 3 records in `.runs/` directories. Resume matches exact
run identities, including configuration, seed, repetition, code and environment.
See `experiments/README.md` for the schema and legacy export.

Genetic search components live in `src/genetic/`. Ancestry diagnostics remain
off by default; pass `track_ancestry=true` to `GeneticIterator` to retain
parent history for diagnostic printing. See [genetic search notes](docs/genetic-search.md)
for the component map, behavior guarantees, profiling command and the discarded
replacement optimization awaiting discussion.
