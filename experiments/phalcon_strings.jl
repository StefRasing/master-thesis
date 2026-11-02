using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/PhalconModule.jl")
using .Phalcon

repetitions = 1
run = ARGS[1]
path = "data/phalcon_strings/phalcon_strings$(run).json"
store = true

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# Results in 124 problems
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

for (problem, grammar) in zip(problems, grammars)
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    test_spec = [1]
    train_spec = setdiff(eachindex(problem.spec), test_spec)
    train_problem = Problem(problem.name, problem.spec[train_spec])
    test_problem = Problem(problem.name, problem.spec[test_spec])

    for _ in 1:repetitions_to_perform
        rule_cost_func = r -> r isa Expr
        rule_costs = Int[rule_cost_func(rule) for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = train_problem,
            cost = _ -> 0,
            population_size = 20,
            candidate_pool_size = 2000,
            max_generations_without_improvement = 10,
            max_extension_size = 1,
            max_initial_population_size = 1,
            max_size = 50,
            rule_costs = rule_costs,
            max_output_bytes = 1024^2,
        )

        solution, result = phalcon(
            iterator = iterator,
            max_number_of_properties = 20,
            property_types = [:ntString, :ntInt, :ntBool],
            max_property_cost = 3,
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
