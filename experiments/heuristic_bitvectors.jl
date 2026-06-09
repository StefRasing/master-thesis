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


repetitions = 5
path = "data/heuristic_bitvectors.json"

benchmark = HerbBenchmarks.PBE_BV_Track_2018
RuntimeGeneratedFunctions.init(benchmark)

# Only keep problems with 10 or less I/O examples
# Results in 151 problems
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && length(getfield(benchmark, s).spec) <= 10]
problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

for (problem, grammar) in zip(problems, grammars)
    repetitions_to_perform = repetitions - performed_repetitions(path, problem.name)

    for _ in 1:repetitions_to_perform
        rule_costs = Int[rule isa Expr for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = problem,
            cost = outputs_and_targets -> sum(hamming_distance(output, target) for (output, target) in outputs_and_targets),
            population_size = 10,
            candidate_pool_size = 2000,
            max_generations_without_improvement = 4,
            max_extension_size = 1,
            max_initial_population_size = 1,
            rule_costs = rule_costs,
        )

        start = time()
        initialize!(iterator)
        solution = find_solution(iterator)
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