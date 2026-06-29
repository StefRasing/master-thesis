using JSON3
using HerbBenchmarks

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
task_names = [String(s)[9:end] for s in Base.names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

absynthe_tasks = []
data = JSON3.read(read("data/absynth/absynth_strings.json", String), Vector{Any})
for obj in data
    push!(absynthe_tasks, obj["problem_name"])
end

# load data
data = JSON3.read(read("data/phalcon_strings.json", String), Vector{Any})

# filter entries
filtered = filter(x -> x["problem_name"] in absynthe_tasks, data)

path = "data/absynth/phalcon_strings_absynth.json"

# write back to file
open(path, "w") do io
    JSON3.pretty(io, filtered)
end
