# Bitvector provenance and baseline alignment

Investigation date: 5 November 2026. This is a research recommendation; experiment code and existing results have not been changed.

## Main finding

Keep the bitvector domain. Your ten-example problems overlap directly with an established benchmark family. The closest practical comparisons are Duet, Simba, and DryadSynth-BV. The obstacles are grammar and evaluation alignment, rather than an absence of shared problems.

## What the local experiment actually selects

`experiments/src/benchmarks.jl` selects `HerbBenchmarks.PBE_BV_Track_2018` and filters on `length(problem.spec) <= 10`.

Static inspection of the local benchmark definitions gives:

| Quantity | Count |
| --- | ---: |
| Problems in the parent module's data file | 753 |
| Selected problems | 151 |
| Selected problems with exactly ten examples | 151 |
| Selected `PRE_*_10` problems | 150 |
| Additional selected problem | `if0_70_10` |

All 151 selected names occur in the official 2018 benchmark index. The index contains 753 `.sl` files in `comp/2018/PBE_BV_Track/`. Index commit: `13c8deb68a873635879c9a69bc78caebd340f646`. Matching names establish an upstream mapping; I did not compare every local file's complete grammar and examples against every upstream original.

The local grammar uses 64-bit values, constants zero and one, one argument, bitwise operations, addition, fixed shifts by 1/4/16, and a restricted conditional. `im_cvc(x,y,z)` tests **x == 1**; `if0_cvc(x,y,z)` tests **x == 0**. Preserve this distinction in any exporter. The upstream `PRE_100_10.sl` defines `im` with the same equality-to-one semantics.

Sources: [official 2018 suite](https://github.com/SyGuS-Org/benchmarks/tree/master/comp/2018/PBE_BV_Track), [example upstream grammar](https://raw.githubusercontent.com/SyGuS-Org/benchmarks/master/comp/2018/PBE_BV_Track/PRE_100_10.sl).

## Historical origin

The 2016 competition report explains that 450 PBE bitvector benchmarks came from the 2013 ICFP Programming Competition, using generated bitvector programs assembled from small minimal program fragments. Another 300 benchmarks using the same grammar were submitted by Arjun Radhakrishna. Thus the family is principally synthetic program recovery, rather than a collection of independently curated real-world tasks. The report establishes family history; it does not by itself explain every file or the extra three instances in the 2018 snapshot.

Source: [SyGuS-Comp 2016 report, §2.1](https://sygus-org.github.io/comp/2016/report.pdf).

## Direct artifact verification

I downloaded the public [Simba PLDI 2023 artifact](https://github.com/yhyoon/pldi2023-artifact) at commit `eb816fabe96e09c73fdcb5a7fbd781b11fea3afb` and compared the ten-example local tasks against its `bench/bitvec-cond/` files.

**150/150 `PRE_*_10` tasks have exactly the same ordered I/O pairs**, under the mapping `PRE_100_10 -> bench/bitvec-cond/100_10.sl`. This checks all 1,500 pairs. The accompanying CSV records each mapping and the artifact's bundled result status/time.

The artifact's `sample_result.tar.gz` contains solution definitions for **150/150 from Simba** and **132/150 from Duet**, with 18 Duet timeouts. These are observations from bundled historical output, not independent reruns or held-out accuracy measurements. Hardware, grammar, and protocol differ from your experiment.

The extra `if0_70_10` has exactly the same ordered examples as local `PRE_70_10`, but uses `if0` instead of `im`. It is a grammar variant, not an independent I/O task. Report it separately or use the 150-task intersection for the external comparison; do not silently count it as a new underlying function.

**Critical grammar difference:** the artifact replaces the original restrictions with a broad grammar containing multiplication, division, remainder, variable shifts, subtraction, constants 0–16, Boolean expressions, and general `ite`. Your current results cannot be compared directly with its published totals.

The [Simba paper, §5](https://arxiv.org/html/2304.10768) explicitly documents this grammar replacement and evaluates 750 BitVec-Cond instances, with a one-hour timeout. It does not evaluate Probe on this conditional family.

## Baseline choices

| Solver | Relevant benchmark use | Recommendation |
| --- | --- | --- |
| Duet (POPL 2021) | The directly matched BitVec-Cond family; bidirectional synthesis | Essential baseline, preferably the version bundled with Simba for reproducibility |
| Simba (PLDI 2023) | Same matched family; abstract interpretation pruning | Essential baseline; artifact includes code, inputs, and historical output |
| DryadSynth-BV (POPL 2024) | Explicitly evaluates all 753 instances of the **2018** PBE-BV track with the standard case-splitting grammar | Particularly close to your original suite; strong third baseline |
| cvc5 | General SyGuS solver | Useful additional baseline; pin a version and validate the input conversion |
| Hope (POPL 2026) | Reports 750 Bitvec-cond tasks alongside deobfuscation and Hacker's Delight | Relevant newer comparison; inspect artifact availability and grammar support before committing |
| Probe (2020) | Bitvector support, but the cited evaluations exclude this conditional family | Not a primary baseline for your present tasks; consider it on a separate supported HD suite |
| Merlin (POPL 2026) | 549 BV tasks: 49 HD and 500 deobfuscation; excludes conditional benchmarks | Conceptually relevant to search guidance, but its published suite does not directly match yours |

DryadSynth's paper uses a ten-minute timeout and compares CVC4, Duet, Simba, and Probe where applicable. Its implementation offers ChatGPT assistance and optional examples from a reference implementation. For your main comparison, disable external-model assistance and ensure no extra examples or reference answers reach synthesis. Record the actual configuration. Source: [DryadSynth paper, §7](https://cap.ecn.purdue.edu/dryadsynth/popl2024authver.pdf), [implementation](https://github.com/purdue-cap/DryadSynth).

cvc5 supports SyGuS2; legacy 2018 input syntax may require conversion. Source: [cvc5 paper](https://cvc5.github.io/papers/2022/BarbosaBBKLMMMN-TACAS22.pdf).

Hope reports 750 conditional BV tasks and compares against Duet and Simba. I found its paper, but did not establish a runnable public artifact in this investigation. Source: [Hope paper](https://doi.org/10.1145/3776694).

Merlin omits case-splitting benchmarks and removes conditionals from some other grammars. Its published headline scores therefore cannot stand in for performance on your 151 tasks. Sources: [Merlin paper, §6](https://arxiv.org/html/2511.02491v1), [code](https://github.com/J4K0B/Merlin).

## Recommended experiment design

Use two separately reported evaluations.

### A. Shared-task synthesis efficiency

Use the 150 matched tasks, supply **all ten examples**, and give every solver the **same grammar**. Begin with your original grammar to minimize changes to PHALCON. Confirm each baseline accepts its helper functions or apply semantics-preserving lowering. If a solver requires a broader grammar, run a separately labelled experiment in which every solver receives that grammar.

Use one common timeout, hardware configuration, memory limit, and CPU budget. Ten minutes is a reasonable initial budget and matches DryadSynth's paper, but a pilot should determine feasibility. Report problems solved, independently validated example consistency, a cactus plot, and timeouts/failures. Distinguish cold startup and Julia compilation from warmed search timing. Compare program size only under an explicit common counting convention, since helpers and DAG sharing affect size.

This experiment directly addresses the standard synthesis-efficiency question and still respects your ten-example cap. It requires reruns; historical aggregate scores are only context.

### B. Small-example generalization

Keep your current five-fold design if it serves your research question: ten-example tasks give **eight synthesis examples and two held-out examples per fold**. Export exactly the same eight examples for every baseline, independently execute the returned program on the two held-out inputs, and never use test outcomes to choose programs or guide search.

Report training consistency and held-out accuracy separately, plus the fraction of tasks/folds for which all held-out outputs are correct. Describe these as finite-sample generalization results, not proof of recovering the intended function. Account for five independent searches per task when reporting computation. Average uncertainty at task level rather than treating the five folds as independent tasks.

An optional stronger evaluation keeps ten synthesis examples and tests against the corresponding 100/1,000-example variants. I checked that, for each of the 150 matched tasks, the ten original I/O pairs have **zero overlap** with the union of the artifact's corresponding larger variants. However, matching suffixes and disjoint pairs do not prove a common intended function: establish that relationship before treating them as ground truth. Never give these additional examples to synthesis in a ten-example experiment.

If you use any related variants for tuning or offline learning, group splits by underlying task family. Different example sets from the same target should not become independent training/test tasks.

## Hacker's Delight as an additional suite

Your local benchmark repository already contains `PBE_BV_Track_2018.Hackers_Delight`, with 27 problems and ten sampled examples each. The current experiment adapter does **not** select this submodule. It could broaden evaluation and make Probe relevant, but it is a locally sampled PBE conversion of relational specifications, so published CEGIS results are not directly comparable.

Its local README also records Boolean-output problems, deliberate sampling choices, and discrepancies between natural-language comments and upstream formal specifications. Use the formal specification as the target, support the relevant output sorts, publish the example sampling procedure, and rerun baselines on exactly the same samples. Do not mix the 27 local problems with papers' 44/49 HD variants as though they were identical suites.

## Suggested paper wording

> We evaluate on the 150 ten-example instances shared by the SyGuS-Comp 2018 PBE-BV suite and the BitVec-Cond suite distributed with Simba. We verified equality of all input-output pairs under a filename mapping. All compared solvers receive identical examples and grammars. We report synthesis efficiency using all ten examples separately from generalization under five-fold evaluation using eight examples for synthesis and two for testing.

Use this wording after the proposed baseline reruns and grammar alignment have actually been completed. At present, only provenance and I/O overlap have been verified.

## Concrete next steps

1. Freeze the 150-task manifest and upstream/artifact commits; retain `if0_70_10` as a separately labelled variant.
2. Export the original grammar and examples to solver-compatible SyGuS, preserving width and conditional semantics.
3. Pilot Duet, Simba, and DryadSynth on a fixed small selection with identical grammar and ten examples. Treat parser or unsupported-operation failures separately from timeouts.
4. Run the common 150-task synthesis comparison, then the same baselines on your eight/two folds.
5. Keep heuristic and unguided/internal ablations to isolate the contribution of property invention from external solvers' implementation and domain knowledge.

No baseline was built or executed during this investigation. The CSV's times are historical artifact times and must not be presented as new measurements.
