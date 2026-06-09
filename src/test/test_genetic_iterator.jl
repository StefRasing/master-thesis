using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays

include("genetic_iterator.jl")
include("levenshtein.jl")

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)
problem = benchmark.problem_11604909
grammar = benchmark.grammar_11604909


function cost(outputs_and_targets) 
    sum(levenshtein(output, target) for (output, target) in outputs_and_targets)
end

iterator = GeneticIterator(grammar, :ntString,
    benchmark = benchmark,
    problem = problem,
    cost = cost,
    population_size = 20,
    candidate_pool_size = 2000,
    max_generations_without_improvement = 5,
    max_extension_depth = 2,
    max_extension_size = 4,
)

solution = find_solution(iterator)
@show solution
@show rulenode2expr(solution, grammar)
# local_optimum_outputs(iterator)

# for (i, p) in enumerate(iterator)
#     i == 1000 && break

#     e = rulenode2expr(p, grammar)
#     individual = iterator.population[findfirst(e -> e.program == p, iterator.population)]
#     v = individual.outputs
#     c = individual.cost
#     println()
#     # @show p
#     @show e
#     @show v
#     @show c
#     @show i

#     c == -Inf && break
# end