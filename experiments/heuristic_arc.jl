using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/heuristics.jl")

repetitions = 1
run = ARGS[1]
range_i = ARGS[2]
path = "data/heuristic_arc/heuristic_arc_$(run)$(range_i).json"

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
)[range_i]

for problem in problems[range]
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    test_spec = [1]
    train_spec = setdiff(eachindex(problem.spec), test_spec)
    train_problem = Problem(problem.name, problem.spec[train_spec])
    test_problem = Problem(problem.name, problem.spec[test_spec])

    for _ in 1:repetitions_to_perform
        max_length = maximum([max(maximum(length, values(io.in)), length(io.out)) for io in train_problem.spec])
        rule_costs = Int[rule isa Expr && !(rule.args[1] in [:objects, :asgrid]) for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = train_problem,
            cost = outputs_and_targets -> sum(hamming_distance(output, target) for (output, target) in outputs_and_targets),
            population_size = 20,
            candidate_pool_size = 10000,
            max_generations_without_improvement = 4,
            max_extension_size = 1,
            max_initial_population_size = 1,
            max_size = 50,
            rule_costs = rule_costs,
            prune_node_by_output = (io, y) -> length(y) > 3*max(maximum(length, values(io.in)), length(io.out))
        )

        start = time()
        initialize!(iterator)
        solution = find_solution(iterator)
        end_time = time()

        interpreter = HerbInterpret.make_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
        solved_test_examples = interpreter(solution, test_problem.spec) == [io.out for io in test_problem.spec]

        result = OrderedDict(
            "problem_name" => iterator.problem.name,
            "solved_train_examples" => !isnothing(solution),
            "solved_test_examples" => "",
            "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
            "programs_enumerated" => iterator.programs_evaluated,
            "execution_time" => end_time - start,
        )

        append_result(path, result)
    end
end