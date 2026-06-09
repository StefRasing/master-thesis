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
            cost = outputs_and_targets -> sum(hamming_distance(output, target) for (output, target) in outputs_and_targets),
            population_size = 10,
            candidate_pool_size = 10000,
            max_generations_without_improvement = 4,
            max_extension_size = 1,
            max_initial_population_size = 1,
            rule_costs = rule_costs,
            prune_node_by_output = (io, y) -> length(y) > 3*max(maximum(length, values(io.in)), length(io.out))
        )

        start = time()
        initialize!(iterator)
        solution = run_with_timeout(60*30) do 
            find_solution(iterator) 
        end
        result = OrderedDict(
            "problem_name" => iterator.problem.name,
            "solved" => !isnothing(solution),
            "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
            "programs_enumerated" => iterator.programs_evaluated,
            "execution_time" => time() - start,
        )

        append_result(path, result)
    end
end