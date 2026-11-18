# Phalcon batch plots

Regenerate from the repository root with:

```sh
julia --project=. experiments/plot_phalcon_batch.jl
```

Optional positional arguments select the snapshot and output directories. Add --bounds to display best/worst repetition envelopes. Each figure is exported as SVG, PDF, and PNG.

The dataset contains five repetitions of 449 strings folds and 755 bitvector folds for each property cap (5, 10, 20, 40). Population size is 100, the property enumeration budget is 10,000, and the timeout is 1,800 seconds per fold. The loader verifies identities, complete fold/run coverage, and matched test splits across caps and repetitions.

Performance curves show mean fold accuracy across repetitions against each fold's own cost. Solid lines show held-out success and dotted lines show training success. Bounds are disabled by default. When enabled, failed repetitions have infinite solve cost.

The property enumeration histogram counts each recorded batch invention attempt once. It uses the earliest enumeration index among selected 1-agreement properties, with a separate no-hit bin. Searches that finish before property invention are excluded. Batch Phalcon enumerates the whole budget and ranks distinct agreement patterns, so this index describes the first selected hit, rather than the stopping point of enumeration.

Timing bars show mean logged time per fold across all repetitions, including zero for skipped phases. Batch phases are initial sampling, property invention, and guided program search. Logged phase durations may exclude interrupted phases and overhead.

The final histogram counts properties installed for held-out-solved fold-runs, pooled over all five repetitions.

Default Phalcon is included from data/phalcon_ablation/daic-uncapped-20261112-pop100. It uses population 100, a 1,800-second timeout, 10,000 property evaluations per invention round, and uncapped property rounds. All problem/fold/repetition identities and held-out indices are checked against the batch records.

The invention histogram counts each default Phalcon invention round as an attempt, while each batch contributes at most one attempt. Their raw attempt counts therefore reflect different numbers of rounds. Timing aggregates logged durations into initial search, total invention, and all subsequent search. The properties-used histogram groups counts of 21 and above in a final 21+ bin.

Both performance graphs include one horizontal reference line per benchmark for default Phalcon's held-out accuracy using at most one property. Each level is computed from the matched default records as the mean fold accuracy over the five repetitions. The at-most-one level includes zero-property solves.

Figures 06 and 07 compare each batch cap separately with default Phalcon on their shared held-out solves. Records are paired by problem, fold, and repetition after verifying identical held-out indices. Each panel conditions on both methods passing all test examples in that fold-run. Curves are cumulative percentages of this shared subset, normalized separately per repetition and averaged over five repetitions, so both curves end at 100%. Panel n is the shared fold-run count pooled across repetitions. Different batch caps have different shared subsets. The companion shared_solves_summary.tsv reports paired faster/fewer counts on the same subsets.
