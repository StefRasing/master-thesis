using JSON3
using HerbBenchmarks

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
task_names = [String(s)[9:end] for s in Base.names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]
string_problems = ["problem_$name" for name in task_names if getfield(benchmark, Symbol("grammar_", name)).rules[1] == :ntString]

# load data
# data = JSON3.read(read("data/phalcon_strings.json", String), Vector{Any})
data = JSON3.read(read("data/nonsense_phalcon_strings.json", String), Vector{Any})

# filter entries
filtered = filter(x -> x["problem_name"] in string_problems, data)

path = "data/phalcon_strings_only_string_outputs.json"
path = "data/nonsense_phalcon_strings_only_string_outputs.json"

# write back to file
open(path, "w") do io
    JSON3.pretty(io, filtered)
end


for (problem, grammar) in zip(problems, grammars)
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    # Skip non-string output problems
    if grammar.rules[1] != :ntString
        result = OrderedDict(
            "problem_name" => problem.name,
            "solved" => false,
            "solution" => nothing,
            "programs_enumerated" => 0,
            "execution_time" => 0,
        )

        for _ in 1:repetitions_to_perform
            append_result(path, result)
        end

        continue
    end
end