using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays

include("genetic_iterator.jl")
include("new_bus.jl")
include("property_synthesizer.jl")
include("phalcon.jl")

# using Profile, ProfileView
# Profile.clear()

benchmark = HerbBenchmarks.PBE_BV_Track_2018
RuntimeGeneratedFunctions.init(benchmark)
problem_grammar_pair = filter(pg -> length(pg.problem.spec) <= 10, get_all_problem_grammar_pairs(benchmark))[1]
problem = problem_grammar_pair.problem
grammar = problem_grammar_pair.grammar

iterator = GeneticIterator(grammar, :Start,
    benchmark = benchmark,
    problem = problem,
    cost = _ -> 0,
    population_size = 10,
    candidate_pool_size = 2000,
    max_generations_without_improvement = 3,
    max_extension_depth = 2,
)

solution = phalcon(
    iterator = iterator,
    max_number_of_properties = 15,
    minimal_increase_property = 0.8,
    maximum_increase_property = 0.9,
    max_property_size = 6,
)

println()
if !isnothing(solution)
    expr = rulenode2expr(solution, grammar)
    @show expr
else
    println("Search failed")
end

# ProfileView.view()