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

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# Results in 129 problems and 105 problems with string outputs
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
task_names = task_names[[1]]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

for (problem, grammar) in zip(problems, grammars)
    repetitions_to_perform = 1

    test_spec = [1]
    train_spec = setdiff(eachindex(problem.spec), test_spec)
    train_problem = Problem(problem.name, problem.spec[train_spec])
    test_problem = Problem(problem.name, problem.spec[test_spec])
    
    # Skip non-string output problems
    if grammar.rules[1] != :ntString
        result = OrderedDict(
            "problem_name" => problem.name,
            "solved" => false,
            "solution" => nothing,
            "programs_enumerated" => 0,
            "execution_time" => 0,
        )

        for _ in 1:repetitions_to_perform
            append_result(path, result)
        end

        continue
    end

    for _ in 1:repetitions_to_perform
        max_length = maximum([max(maximum(length, values(io.in)), length(io.out)) for io in train_problem.spec])
        rule_costs = Int[rule isa Expr for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = train_problem,
            cost = outputs_and_targets -> sum(levenshtein(output, target) for (output, target) in outputs_and_targets),
            population_size = 20,
            candidate_pool_size = 2000,
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
            "train_test_split" => (train_spec, test_spec),
            "solved_train_examples" => !isnothing(solution),
            "solved_test_examples" => solved_test_examples,
            "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
            "programs_enumerated" => iterator.programs_evaluated,
            "execution_time" => end_time - start,
        )

        @show result
    end
end