using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer.jl")
include("../src/phalcon.jl")
include("../src/ARC_property_grammar.jl")

# repetitions = 5
run = ARGS[1]
range_i = ARGS[2]
path = "data/phalcon_arc_$(run)$(range_i).json"

benchmark = HerbBenchmarks.ARC_AGI1
RuntimeGeneratedFunctions.init(benchmark)

# 400 arc training problems
problems = benchmark.training_problems()
grammar = benchmark.grammar_hodel

range = Dict(
    "a" =>  1:100,
    "b" => 101:200,
    "c" => 201:300,
    "d" => 301:400,
)[ARGS[2]]

for problem in problems[range]
    # repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)
    repetitions_to_perform = 1

    for _ in 1:repetitions_to_perform
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

        result = phalcon(
            iterator = iterator,
            max_number_of_properties = 20,
            property_types = [:Grid, :Objects, :Object, :Indices, :IntContainer, :IntegerTuple, :Integer, :Boolean],
            minimal_increase_property = 0.7,
            max_property_cost = 3,
            grammar_to_property_grammar = _ -> _grammar_to_property_grammar(property_grammar_hodel),
            rule_costs = rule_costs,
            timeout = 60*30,
        )

        append_result(path, result)
    end
end