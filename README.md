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
include("src/Phalcon.jl")
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
the sibling `HerbInterpret.jl` checkout. The unused alternative property synthesis
implementation in `src/property_synthesizer_playground.jl` is not loaded by the
module; all experiment runners use the shared implementation.
