# ARC enumeration and equality profile (baseline)

This report records the baseline investigation. Periodicity and per-run property-interpreter reuse have since been implemented; see [implementation measurements](ARC_OPTIMIZATION_RESULTS.md).

Measured on 2026-11-03, Julia 1.12.5, local HerbBenchmarks checkout including the primitive allocation improvements. Production search/equality/periodicity implementations were not changed by this investigation.

## Method

Three ARC tasks (training indices 1, 2, 5), seed 42, standard Phalcon options, 12-second cooperative trial budgets. The last example remains held out. Each task also has a separate property-enumeration measurement on its actual initialized 20-program population (not a converged genetic population), with property cost 3 and a 12-second budget. Standard search warm-up and interpreter preparation precede trials; property probes have a three-second warm-up. Property probes still generate fresh interpreters on every invocation, so warm-up does not eliminate compilation. Trial budgets can overshoot inside individual calls. These are early-stage profiles, not a full-suite or long-run steady-state study.

Sampling uses Julia Profile. Process-local wrappers count/time Object and Indices equality and separately time Cartesian-product storage after child banks have been obtained. Counts include DSL equality(Object,Object). No source-level algorithm changes are used in the measured runs. Instrumentation adds overhead, especially to short equality calls. The timer for combination storage excludes child-bank construction. The sample key `combination_materialization` in saved JSON is inclusive of child-bank construction and MUST NOT be interpreted as the storage-only cost. Flat profiles also include idle-thread snapshots; do not divide by all snapshots to obtain active-CPU percentages. Timers are more useful for the two narrowly scoped questions.

## Measurements

| Task / phase | Wall (s) | Product storage (ms) | Set equality (ms) | Total allocated (GB) | Product storage allocated (MB) | GC (s) |
|---|---:|---:|---:|---:|---:|---:|
| task1_properties | 9.141 | 2.497 | 14.225 | 0.930 | 0.633 | 0.537 |
| task1_search | 12.359 | 11.763 | 2.168 | 1.695 | 19.280 | 2.049 |
| task2_properties | 4.337 | 0.413 | 0.676 | 1.178 | 0.085 | 0.579 |
| task2_search | 13.076 | 6.195 | 0.638 | 2.830 | 9.083 | 1.099 |
| task5_properties | 12.103 | 0.566 | 7.300 | 4.661 | 0.190 | 4.972 |
| task5_search | 12.140 | 8.748 | 0.000 | 2.202 | 11.645 | 2.206 |

The task names are `007bbfb7`, `00d62c1b`, and `045e512c`. Property probes enumerated 3,712, 494 and 633 candidates respectively; the third timed out. The largest completed combination batch was 45,824 tuples. No instrumented equality call compared an object/indices vector with itself by identity.

The recorded product-storage timer covers completed Cartesian products; an interrupted product would not be charged by the original measurement wrapper. The profiling script now uses try/finally to cover this case in future runs. This limitation does not affect the completed, untimed-out property probes for tasks 1 and 2.

## Interpretation

- Product storage accounted for 0.005–0.095% of measured wall time, and at most 1.14% of total allocated bytes. Streaming could reduce transient memory, but these runs provide no evidence of a large overall speedup from it. This does not rule out larger Cartesian products at deeper costs.
- Object/Indices set equality accounted for at most 0.16% of wall time. Caching comparison representations would speed individual comparisons but is not a priority for these workloads. A same-reference shortcut would have helped none of the observed calls.
- Enumeration itself remains expensive because it interprets many candidates. Sampling places substantial time below `assemble -> interpreter`, including compiler work. `find_property!` calls `make_output_interpreter` each time, generating fresh functions; interpreter reuse deserves a separate controlled experiment. A measured runtime improvement from reuse has not yet been established.
- The clearest allocation hotspot in task 5 is periodicity: `hperiod`/`vperiod`, including `order_by` applying them across objects, repeatedly build sets and shifted objects. Its property probe allocated 4.661 GB and spent 4.972 of 12.103 seconds in GC (~41%). Allocation totals include compilation; sampled stacks identify periodicity-related set construction as a prominent source, not the sole source.

## Diagnostic microbenchmarks

For two reordered equal 900-cell objects, current equality took ~31.8 microseconds and allocated 102,752 bytes. Comparing prebuilt sets took ~5.63 microseconds with zero new allocations. This excludes set preparation and adds retained-memory requirements. Reordered equal Objects also produced different array hashes: any canonical representation/deduplication redesign must explicitly decide equality and hashing together.

A periodicity prototype normalizes once, creates one membership Set, then checks translated cells directly. It uses a concrete typed helper so the hot loop remains inferred. On the actual first 21×21 input of task 5:

| Primitive | Current (µs) | Prototype (µs) | Current bytes | Prototype bytes |
|---|---:|---:|---:|---:|
| hperiod | 192.57 | 16.04 | 1,028,944 | 38,400 |
| vperiod | 193.80 | 16.08 | 1,030,624 | 38,400 |

That is about 12× faster and 96% fewer allocated bytes. On a random 30×30 object, the corresponding operation speedups were 32× and 54×. These are microbenchmarks, not measured whole-search speedups. The prototype passed equality-of-results assertions for 100 randomized sparse objects, including empty objects, repeated entries and negative coordinates, plus the two benchmark grids. Production periodicity primitives are unchanged.

## Suggested order

1. Implement and test the periodicity improvement; rerun these profiles to measure the actual search gain.
2. Measure reuse of property interpreters on identical grammars/modules, without retaining task outputs or enumeration state.
3. Revisit streaming combinations if larger/deeper profiles show substantial transient lists.
4. Revisit cached equality representations if longer searches show a substantial equality share.

## Reproduction

```sh
julia --project=. --startup-file=no experiments/performance/arc_search_profile.jl /tmp/arc-search-profile
julia --project=. --startup-file=no experiments/performance/arc_equality_bench.jl
julia --project=. --startup-file=no experiments/performance/arc_periodicity_bench.jl
```

Raw JSON measurements and flat sampling profiles are in `arc_profile_results/`. Julia emitted world-age warnings for generated-rule bindings during preparation/execution; the runs completed. This is another reason not to treat these short runs as a compilation-free steady-state result.
