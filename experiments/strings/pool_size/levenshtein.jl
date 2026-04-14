using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using DataFrames, RuntimeGeneratedFunctions, Plots
using HerbBenchmarks.PBE_SLIA_Track_2019

include("../../../src/neighborhood_search.jl")
include("../../../plots/time_over_solution_size.jl")


#====================================

    Step 1: Setup

=====================================#

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# univ problems have too many terminals to run in a descent amount of time...
# Also, cut off I/O examples if there are more than 10, otherwise it will take too long
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "univ"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]
problems = [Problem(problem.name, problem.spec[1:min(end, 10)]) for problem in problems]

# Filter on string problems
problem_grammar_pairs = collect(zip(problems, grammars))
filter!(pg -> last(pg).rules[1] == :ntString, problem_grammar_pairs)


function levenshtein_fast(a::AbstractString, b::AbstractString)
    m, n = length(a), length(b)

    if m < n
        a, b = b, a
        m, n = n, m
    end

    prev = collect(0:n)
    curr = similar(prev)

    for i in 1:m
        curr[1] = i
        for j in 1:n
            cost = a[i] == b[j] ? 0 : 1
            curr[j+1] = min(
                prev[j+1] + 1,
                curr[j] + 1,
                prev[j] + cost
            )
        end
        prev, curr = curr, prev
    end

    return prev[n+1]
end

#====================================

    Step 2: Define synth function

=====================================#

function path_to_solution(pool_entry)
    if isnothing(pool_entry.parent)
        return []
    end

    (p, i) = pool_entry.parent
    entry = (
        :program => p.program,
        :cost => p.cost,
        :pool_index => i,
    )
    
    return [path_to_solution(p); entry]
end

function levenshtein_synthesizer(;
    iterator::NeighborhoodSearch,
    problem::Problem,
)
    # Collect stats: program enumerated and solution
    solution = missing

    # Loop over programs
    for program in iterator
        # Success: all I/O examples solved
        all(output == io.out for (output, io) in zip(program._val, problem.spec)) && (solution = program; break)
    end

    println("Finished $(problem.name)")

    # Return results
    (
        :problem_name => problem.name,
        :solved => !ismissing(solution),
        :solution => solution,
        :programs_enumerated => iterator.programs_evaluated,
        :path_to_solution => ismissing(solution) ? missing : path_to_solution(iterator.pool[findfirst(e -> e.program == solution, iterator.pool)]),
    )
end


#====================================

    Step 3: Define default parameters

=====================================#

# Define default hyperparameters
default_params = (
    pool_size = 5,
    max_extension_depth = 1,
    max_extension_size = 1,
)

arguments = (
    synth = levenshtein_synthesizer,
    heuristic = levenshtein_fast,
    benchmark = benchmark,
)

#====================================

    Step 4: Benchmark

=====================================#

params = n -> merge(default_params, (pool_size = n,))
path = n -> "data/strings/pool_size/levenshtein/n=$n.jld2"
# pool_sizes = [parse(Int64, ARGS[1])]
pool_sizes = [1,2,5,10,20]

data = [
    @benchmark NeighborhoodSearch params=params(n) problem_grammar_pairs=problem_grammar_pairs args=arguments path=path(n) 
    for n in pool_sizes
]

savefig(problems_solved_over_time(data; 
    label = r->"Pool size $(r.params[:pool_size])", 
    title = "Problem solved over time for Levensthein",
    xscale = :log10,
    xlims = [10^-3, 10^1.5],
    xticks = [10.0^n for n in -3:5],
    legend = :topleft,
), "plots/strings/pool_size/levenshtein/problem_solved_over_time.png")

savefig(problems_solved_over_enumerations(data, 
    label = r->"Pool size $(r.params[:pool_size])",
    title = "Problem solved over enumerates for Levensthein",
    xscale = :log10,
    xlims = [10^1.5, 10^6],
    xticks = [10.0^n for n in 2:7],
    legend = :topleft,
), "plots/strings/pool_size/levenshtein/problem_solved_over_enumerations.png")

savefig(time_over_solution_size(data, 
    label = r->"Pool size $(r.params[:pool_size])",
    title = "Execution time vs solution size for Levensthein",
    ylim = [0,20]
), "plots/strings/pool_size/levenshtein/time_over_solution_size.png")
