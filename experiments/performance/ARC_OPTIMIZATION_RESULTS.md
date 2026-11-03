# ARC periodicity and property-interpreter reuse

Implemented 2026-11-03 against the local HerbBenchmarks checkout (Julia 1.12.5).

## Implementation

- HerbBenchmarks `hperiod` and `vperiod` normalize once and build one membership Set. Each candidate period checks translated cells directly and stops at its first mismatch. A concretely typed helper keeps the inner loop inferred. Empty/singleton objects, sparse objects, duplicates, conflicting colors at a position, negative coordinates and incomplete final repetitions preserve the previous semantics.
- Phalcon lazily builds one property-output interpreter per run and reuses it for that unchanged property grammar and benchmark module. Its first construction/compilation remains inside the timed property search. There is no global cache and no sharing across Phalcon runs.
- `find_property!` accepts an optional prebuilt `interpreter`. Standalone callers can reuse generated code for the same unchanged grammar/module pair. Every call still constructs fresh input dictionaries and an enumeration bank, so task inputs, outputs, pruning and counters remain independent. Changing the grammar requires a new interpreter.

## Fixed-work comparison

On task `045e512c`, use the same initialized 20-program population and the first 700 interpreted property candidates. Compare equivalent previous periodicity implementations with the production optimized primitives; compare a freshly generated interpreter on every call with a prebuilt, warmed interpreter. A diagnostic process-local switch avoids changing production files. All eight measured runs had identical candidate-rule and output hashes. The benchmark is stopped before interpreting candidate 701. Fresh interpreter construction is included in fresh-call times; the reused path represents subsequent searches, after the first interpreter construction/warm-up.

Two rounds, alternating mode order. Medians:

| Mode | Seconds | Allocated GB | GC seconds |
|---|---:|---:|---:|
| Previous periodicity, fresh interpreter | 4.823 | 7.047 | 0.826 |
| New periodicity, fresh interpreter | 2.205 | 0.657 | 0.052 |
| Previous periodicity, reused interpreter | 3.290 | 6.992 | 0.387 |
| Both optimizations | 1.475 | 0.601 | 0.000 |

Together, the changes made this fixed property-search workload about **3.27× faster**, with **91.5% fewer allocated bytes**. On top of periodicity, interpreter reuse reduced runtime by about **33%**. This is a property-enumeration workload, not a full ARC solve-time claim. Two rounds are a diagnostic comparison, not a statistical performance study; GC and compilation affect timing, particularly the first baseline measurement. Individual baseline times were 5.736 and 3.910 seconds; both-optimized times were 1.468 and 1.481 seconds.

## Repeated sampling profiles

Reran the earlier three-task profiler after both changes. Property probes now reuse their output interpreter after bounded warm-up, matching the intended repeated-search behavior:

| Task | Before seconds / candidates | After seconds / candidates | Outcome |
|---|---:|---:|---|
| 1 | 9.141 / 3,712 | 2.752 / 3,712 | Property found |
| 2 | 4.337 / 494 | 1.604 / 494 | Property found |
| 5 | 12.103 / 633 | 8.380 / 3,979 | Property found |

Task 5 previously timed out at 12 seconds after 633 candidates; it now completed its property search in 8.38 seconds after 3,979 candidates. Its GC time fell from 4.97 to 0.93 seconds, while processing more candidates. These short profiles still include residual compilation. Their first-property preparation differs from a completely warmed repeated search, so use the fixed-work table to attribute improvements.

Full Phalcon probes retained their 12-second cooperative budgets. All three remained unsolved within those short budgets; task 5 still spent its full trial in initial program enumeration and did not reach property invention. Consequently, the measurements establish faster property search and lower allocations, not improved full-suite solve rates or a uniform whole-solver speedup.

## Validation

- Full thesis suite: `julia --project=. --startup-file=no test/runtests.jl` passed (including 22 new assertions comparing fresh/reused interpreters across different targets, changed local outputs, pruning and expired deadlines).
- ARC primitive regressions: 160 existing allocation-improvement assertions and 1,008 new periodicity assertions passed directly against the modified primitive source. The new tests are also registered in HerbBenchmarks' ARC test file. The library's complete ReTestItems suite was not run here because that runner is not installed.
- Fixed-work comparator checked identical candidate-rule/output streams for all four configurations.
- `git diff --check` passed in both repositories.

## Reproduction and raw data

```sh
julia --project=. --startup-file=no experiments/performance/arc_property_comparison.jl /tmp/arc-property-comparison.json
julia --project=. --startup-file=no experiments/performance/arc_search_profile.jl /tmp/arc-search-profile-after
julia --project=. --startup-file=no experiments/performance/arc_periodicity_bench.jl
```

Raw fixed-work measurements: `arc_profile_results/property_comparison.json`.
Original sampling profiles: `arc_profile_results/`; updated profiles: `arc_profile_results/after/`.
The sampling runs emitted the existing Julia world-age warnings for generated rule bindings and completed successfully.
