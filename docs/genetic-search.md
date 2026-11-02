# Genetic search implementation and performance

All components remain in `Phalcon`; `src/genetic_iterator.jl` is the entry point
and defines the iterator configuration. The implementation is split into:

- `nodes.jl`: cached outputs, sparse rule counts, conversion, subtree selection
  and persistent path replacement (rebuild ancestors; share unaffected children).
- `individuals.jl`: individual representation, ordering and equality.
- `evaluation.jl`: output interpretation, pruning and conversion to fitness.
- `population.jl`: individual construction, initialization, fitness updates,
  sorted bounded population admission and observational deduplication.
- `operators.jl`: type-compatible crossover and replace/insert/delete mutation.
- `iteration.jl`: candidate generation, solution search and Julia iteration state.
- `diagnostics.jl`: ancestry printing.

Initialization enumerates extensions by output equivalence and seeds the
population. A generation snapshots the current individuals larger than one node
as its selection pool. Each batch draws two parents uniformly from that snapshot,
mutates each, crosses them, then mutates the crossover. The four candidates are
admitted in that order. Cost orders the population, with program size breaking
ties; equivalent outputs compete within an equal-cost range. Candidates are
counted even when rejected. The solution interface and Julia iteration interface
retain their existing, distinct stability checks.

## Optional ancestry

`GeneticIterator(...; track_ancestry=false)` omits parent, crossover and mutation
metadata from newly created individuals and is the default. Pass
`track_ancestry=true` to retain history for diagnostic printing. This does not change operator calls, fitness evaluation,
RNG draws, selection or candidate accounting. Printing an untracked individual
prints just its program. Disabling tracking on an existing iterator does not
remove metadata from individuals already retained; construct a fresh iterator
to avoid that history from the start. Program trees still share subtrees and
cache outputs; this option is not a total memory bound.

## Profile before changing types

Run `julia --project=. benchmarks/profile_genetic.jl` for a warmed-up synthetic
mutation profile (five timing/allocation samples plus Julia's sampling profile).
It uses a fixed initial seed, five rules, one example, and a three-node parent.
Initialization and compilation are outside the measurements. The RNG advances
between samples. This isolates operators; it does not measure realistic
population histories, property synthesis, large DSL outputs or solve rates.

A local run on 2026-11-02 measured 100,000 mutations at 0.44–0.57 seconds and
449–451 MB allocated per sample (other validation processes were running).
Profiles before and after the file split repeatedly included node construction,
interpretation and sparse-vector indexing. These are diagnostic observations,
not evidence of an end-to-end speedup. No abstract fields or callback types were
changed. Profile representative thesis workloads before choosing specialization;
compare compilation, allocations, steady-state runtime and retained memory.

## Discarded replacement: intentionally preserved pending discussion

The `:replace` branch first samples a grammar rule and child extensions, builds
and interprets a node, then overwrites it with a sampled extension of the desired
type. Only the sampled extension reaches `replace_at_path`. Removing the first
construction saves one node interpretation and associated allocations per
replacement mutation. Removing its preparatory sampling also saves RNG work,
but changes subsequent draws and seeded search trajectories. Interpreter and
pruning callbacks also receive fewer calls, which matters if they have effects
or raise exceptions.

Potential next steps to discuss are removing only the discarded construction
(keeping RNG draws), or removing the entire discarded sampling/construction
sequence. Neither is implemented here, and the synthetic profile does not yet
establish a huge end-to-end benefit. The first also needs agreement that fewer
interpreter/pruning calls are acceptable. Compare representative benchmark
runtime and solve rates before accepting the second.

Validation of this refactor included the complete regression suite and an
external before/after trace of 100 mutations (operation, tree, outputs and final
RNG draw), which matched byte for byte. Regression tests additionally compare
five generations with tracking enabled/disabled, including population programs,
costs, evaluation counts, fitness-call counts and RNG state.
