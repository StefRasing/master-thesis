using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays

include("lazy_cost_based_bus.jl")
include("genetic_iterator.jl")
include("property_synthesizer.jl")
include("phalcon.jl")
include("ARC_property_grammar.jl")

# using Profile, ProfileView
# Profile.clear()

benchmark = HerbBenchmarks.ARC_AGI1
RuntimeGeneratedFunctions.init(benchmark)
problem = benchmark.problem_a59b95c0
grammar = benchmark.grammar_hodel
max_length = maximum([max(maximum(length, values(io.in)), length(io.out)) for io in problem.spec])

iterator = GeneticIterator(grammar, :Start,
    benchmark = benchmark,
    problem = problem,
    cost = _ -> 0,
    population_size = 10,
    candidate_pool_size = 5000,
    max_generations_without_improvement = 4,
    max_extension_size = 1,
    max_initial_population_size = 2,
    rule_costs = Int[r isa Expr for r in grammar.rules],
    prune_program_by_output = output -> length(output) > max_length*2
)

solution, individual = phalcon(
    iterator = iterator,
    max_number_of_properties = 5,
    property_types = [:Grid, :Object, :Objects, :Boolean, :Integer, :Indices, :IntegerTuple, :IntContainer],
    # property_types = [:Grid, :Object, :Boolean, :Integer, :IntegerTuple, :IntContainer],
    minimal_increase_property = 0.7,
    max_property_depth = 3,
    grammar_to_property_grammar = _ -> _grammar_to_property_grammar(property_grammar_hodel),
)

println()
if !isnothing(solution)
    expr = rulenode2expr(solution, grammar)
    @show expr

    pretty_print(individual, grammar)
else
    println("Search failed")
end

# ProfileView.view()
