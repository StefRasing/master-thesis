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
problem = benchmark.problem_dbc1a6ce
grammar = HerbBenchmarks.ARC_AGI1.grammar_hodel
max_length = maximum([max(maximum(length, values(io.in)), length(io.out)) for io in problem.spec])
rule_costs = Int[rule isa Expr && !(rule.args[1] in [:objects, :asgrid]) for rule in grammar.rules]

iterator = GeneticIterator(grammar, :Start,
    benchmark = benchmark,
    problem = problem,
    cost = _ -> 0,
    population_size = 10,
    candidate_pool_size = 10000,
    max_generations_without_improvement = 4,
    max_extension_size = 1,
    max_initial_population_size = 1,
    rule_costs = rule_costs,
    prune_node_by_output = (io, y) -> length(y) > 3*max(maximum(length, values(io.in)), length(io.out))
)

solution, individual = phalcon(
    iterator = iterator,
    max_number_of_properties = 1,
    # property_types = [:Boolean, :Integer, :IntegerTuple, :IntContainer, :Indices, :Object, :Objects, :Grid],
    property_types = [:Grid, :Objects, :Object, :Indices, :IntContainer, :IntegerTuple, :Integer, :Boolean],
    minimal_increase_property = 0.95,
    max_property_depth = 3,
    grammar_to_property_grammar = _ -> _grammar_to_property_grammar(property_grammar_hodel),
    rule_costs = rule_costs,
)

println()
if !isnothing(solution)
    expr = rulenode2expr(solution, grammar)
    @show expr

    pretty_print(individual, grammar)
else
    println("Search failed")
end

# Profile.view()