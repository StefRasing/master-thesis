using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/PhalconModule.jl")
using .Phalcon
include("../src/ARC_property_grammar.jl")

repetitions = 1
run = ARGS[1]
range_i = ARGS[2]
path = "data/phalcon_arc/phalcon_arc_$(run)$(range_i).json"
store = true


benchmark = HerbBenchmarks.ARC_AGI1
RuntimeGeneratedFunctions.init(benchmark)

# 400 arc training problems
problems = benchmark.training_problems()
grammar = benchmark.grammar_hodel


problems = problems[Dict(
    "a" =>  1:100,
    "b" => 101:200,
    "c" => 201:300,
    "d" => 301:400,
)[range_i]]

for problem in problems
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    test_spec = [1]
    train_spec = setdiff(eachindex(problem.spec), test_spec)
    train_problem = Problem(problem.name, problem.spec[train_spec])
    test_problem = Problem(problem.name, problem.spec[test_spec])

    for _ in 1:repetitions_to_perform
        rule_cost_func = r -> r isa Expr && !(r.args[1] in [:objects, :asgrid])
        rule_costs = Int[rule_cost_func(r) for r in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = train_problem,
            cost = _ -> 0,
            population_size = 20,
            candidate_pool_size = 10000,
            max_generations_without_improvement = 10,
            max_extension_size = 1,
            max_initial_population_size = 1,
            max_size = 50,
            rule_costs = rule_costs,
            max_output_bytes = 1024^2,
        )

        solution, result = phalcon(
            display_outputs = benchmark.visualize,
            iterator = iterator,
            max_number_of_properties = 20,
            property_types = [:Grid, :Objects, :Object, :Indices, :IntContainer, :IntegerTuple, :Integer, :Boolean],
            max_property_cost = 3,
            grammar_to_property_grammar = _ -> _grammar_to_property_grammar(property_grammar_hodel),
            rule_cost_func = rule_cost_func,
            max_output_bytes = 21 * 1024^2,
            verbose = false,
            timeout = 60*30,
        )

        interpreter = HerbInterpret.make_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
        solved_test_examples = interpreter(solution, test_problem.spec) == [io.out for io in test_problem.spec]

        result["train_test_split"] = (train_spec, test_spec)
        result["solved_test_examples"] = solved_test_examples

        if store
            append_result(path, result)
        else
            println()
            @show result
        end
    end
end