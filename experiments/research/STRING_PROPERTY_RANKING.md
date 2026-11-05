# Rank domain-level string properties

Run from the thesis repository:

```sh
julia --project=. experiments/research/rank_string_properties.jl
```

The default experiment uses all **115** currently eligible SyGuS string tasks:
every I/O example must have exactly one string input (`_arg_1`) and one string
output. This includes short/long/repeat/small variants. Use `--canonical-only`
to follow the main experiment's variant exclusions (**67** eligible tasks).
Tasks are sorted by name for reproducibility.

For each task, enumerate the first **400 valid, behaviorally distinct programs**
in increasing operation cost using PHALCON's `LazyCostBasedBus`. Use the task's
own program grammar and all its supplied examples. Terminals cost zero;
function applications cost one. This is deterministic enumeration, not genetic
sampling or a population selected by fitness. Programs that exactly solve all supplied examples are excluded from the sampled
pool; enumeration continues until it collects the requested number of non-solutions.
Solutions remain available as intermediate subprograms inside the enumerator.
Failed program outputs are excluded. The JSON records solutions skipped and
checks the number of solutions in the final sample (zero).

The property grammar is the intersection of typed productions across the whole
eligible suite (even when using `--tasks` for a pilot), with `_arg_out` added as a
string terminal. Properties can refer to **both input and output**. This retains
shared DSL operations and shared literals, rather than importing task-specific
constants into every property. The exact resulting grammar is saved in JSON.

Enumerate all syntactically distinct properties containing `_arg_out` through
**operation cost 3**, returning `ntString`, `ntInt`, or `ntBool`. This matches
the default PHALCON property cost bound. It does not mean an unbounded space
of every possible property. Unlike PHALCON's task-local property enumeration,
this enumeration does not merge properties by their behavior on one task,
because that could discard properties that differ on another task.

For each property:

1. Start with score zero.
2. On each task, compute its property values on the target output vector.
3. Count sampled programs whose property values equal that vector on **every**
   example. This counts programs, not individual matching examples.
4. If that count is zero, discard the property immediately, as requested.
5. Otherwise add the count to its score and continue to the next task.

Rank surviving properties by **ascending total score**. Properties with full
acceptance are retained; in particular, a constant-valued property containing
`_arg_out` is not discarded merely for being uninformative. Ties use property
cost, result type, and expression. Distinct properties with identical acceptance
patterns are retained rather than silently deduplicated.

## Output

Default: `experiments/research/results/string_property_ranking.json`.

The JSON contains the ranked expressions, total scores, acceptance counts in
task order, each task's 400 sampled program expressions, examples per task,
selection exclusions, exact property grammar, configuration, and script/data
hashes. Invalid target evaluations and output-size violations are counted
separately from zero acceptance. No external baseline or existing experiment
results are modified.

The maximum program cost is 6. Sampling has a cooperative 120-second limit per
task, including interpreter construction. If a task cannot provide all 400
programs, the experiment fails rather than silently changing its weight.
Increase `--max-program-cost` or `--sampling-timeout` if necessary.

Ranking has a cooperative one-hour limit after building its contexts and interpreter. A
timeout saves completed property scores with `complete=false`; such a file
is a **partial ranking**, not the complete enumeration. The script prints progress during sampling and every 1,000 properties scored.
Repeated subexpression outputs are cached with a 512 MiB retained-output budget;
`--cache-bytes 0` disables caching. Cache eviction changes performance only,
not property enumeration, scores, or invalidation. Large string output batches
use a conservative size bound before the exact output-limit check.

## Pilots and options

```sh
# Pilot with exactly 400 programs on two tasks, smaller property bound.
julia --project=. experiments/research/rank_string_properties.jl --tasks 2 --max-property-cost 2 --output /tmp/string-ranking-pilot.json

# The subset used by the main experiments.
julia --project=. experiments/research/rank_string_properties.jl --canonical-only

# All options.
julia --project=. experiments/research/rank_string_properties.jl --help

# Focused correctness checks.
julia --project=. test/string_property_ranking.jl
```

This is exploratory domain analysis: it uses all supplied examples and, by
default, related benchmark variants. Its ranking must not be treated as guidance
learned on a separate training set when reporting results on these same tasks.

## Keep zero-acceptance properties

The optional `--keep-zero-acceptance` flag retains properties even when a task
accepts zero sampled programs. Those zeros contribute zero to the total score;
all tasks are still evaluated. Invalid target values and output-limit violations
remain grounds for exclusion. The default continues to prune zero acceptance.
Use a different output path to preserve the original ranking:

```sh
julia --project=. experiments/research/rank_string_properties.jl --canonical-only --programs 100 --max-property-cost 2 --keep-zero-acceptance --output experiments/research/results/string_property_ranking_canonical_100_cost2_keep_zero.json
```

## Remove properties whose total score is zero

After collecting non-solution samples and ranking with `--keep-zero-acceptance`,
filter the completed JSON into a separate file:

```sh
julia --project=. experiments/research/filter_zero_score_properties.jl INPUT.json OUTPUT.json
```

This keeps a property with counts such as `[0, 2, 0]` (score 2), but removes one
with `[0, 0, 0]` (score 0). It does not change scores, task-level counts, or ordering
of retained rows. The original JSON is untouched, existing output files are not
overwritten, and postprocessing metadata records the source file's hash and the
number of rows removed. The original enumeration and invalidation counts describe
the input ranking; the separate removal count describes this additional filter.
