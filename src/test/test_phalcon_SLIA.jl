using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays

include("lazy_size_based_bus.jl")
include("genetic_iterator.jl")
include("property_synthesizer.jl")
include("phalcon.jl")

# using Profile, ProfileView
# Profile.clear()

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)
problem = benchmark.problem_39060015
grammar = benchmark.grammar_39060015
max_length = maximum(length, vcat([[values(io.in)...; io.out] for io in problem.spec]...))

iterator = GeneticIterator(grammar, :Start,
    benchmark = benchmark,
    problem = problem,
    cost = _ -> 0,
    population_size = 10,
    candidate_pool_size = 2000,
    max_generations_without_improvement = 3,
    max_extension_size = 4,
    prune_program_by_output = output -> length(output) > max_length*5
)

solution = phalcon(
    iterator = iterator,
    max_number_of_properties = 20,
    property_types = Vector{Symbol}(unique(grammar.types)),
    minimal_increase_property = 0.8,
    max_property_size = 10,
)

println()
if !isnothing(solution)
    expr = rulenode2expr(solution, grammar)
    @show expr
else
    println("Search failed")
end

# ProfileView.view()