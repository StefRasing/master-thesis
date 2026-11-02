using HerbBenchmarks
using JSON3


# name = "phalcon_strings"
# name = "heuristic_strings"
name = "crossbeam_strings"

# name = "phalcon_bitvectors"
# name = "heuristic_bitvectors"

# name = "phalcon_arc"
# name = "heuristic_arc"


file = "data/$name.json"

# benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
# task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
# problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
# grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]
# tasks = [p.name for (p, g) in zip(problems, grammars) if g.rules[1] == :ntString && all(t == :ntString for (t,r) in zip(g.types, g.rules) if r isa Symbol && occursin("_arg_", string(r)))]


# Read and merge all arrays
solves = [0,0,0,0,0]
enums = [0,0,0,0,0]

data = JSON3.read(read(file, String))

for (i, x) in enumerate(data)
    !x.solved && continue

    run = (i-1) % 5 + 1
    solves[run] += 1
    enums[run] += x.programs_enumerated
end

@show round.(enums ./ solves)