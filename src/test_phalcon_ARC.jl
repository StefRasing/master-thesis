using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays

include("genetic_iterator.jl")
include("new_bus.jl")
include("property_synthesizer.jl")
include("phalcon.jl")

# using Profile, ProfileView
# Profile.clear()

benchmark = HerbBenchmarks.ARC_AGI1
RuntimeGeneratedFunctions.init(benchmark)
problem = benchmark.problem_007bbfb7
grammar = benchmark.grammar_hodel

iterator = GeneticIterator(grammar, :Start,
    benchmark = benchmark,
    problem = problem,
    cost = _ -> 0,
    population_size = 10,
    candidate_pool_size = 1000,
    max_generations_without_improvement = 3,
    max_extension_depth = 2,
    max_extension_size = 4,
)

function grammar_to_property_grammar(grammar)
    property_grammar = deepcopy(grammar)

    # Set start rule to boolean
    original_starting_symbol = property_grammar.rules[1]
    property_grammar.rules[1] = :Boolean

    # Add 'y' rule and constraint grammar to contain it
    add_rule!(property_grammar, Expr(:(=), original_starting_symbol, :_arg_out))
    addconstraint!(property_grammar, Contains(length(property_grammar.rules)))

    return property_grammar
end

solution = phalcon(
    iterator = iterator, 
    grammar_to_property_grammar = grammar_to_property_grammar, 
    max_number_of_properties = 1,
)

println()
if !isnothing(solution)
    expr = rulenode2expr(solution, grammar)
    @show expr
else
    println("Search failed")
end

# ProfileView.view()