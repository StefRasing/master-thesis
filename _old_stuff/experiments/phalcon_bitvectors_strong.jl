using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer_strong.jl")
include("../src/phalcon.jl")

repetitions = 5
path = "data/phalcon_bitvectors_strong.json"

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
        rule_cost_func = r -> r isa Expr
        rule_costs = Int[rule_cost_func(rule) for rule in grammar.rules]

        iterator = GeneticIterator(grammar, :Start,
            benchmark = benchmark,
            problem = problem,
            cost = _ -> 0,
            population_size = 20,
            candidate_pool_size = 2000,
            max_generations_without_improvement = 4,
            max_extension_size = 1,
            max_initial_population_size = 1,
            rule_costs = rule_costs,
        )

        result = phalcon(
            iterator = iterator,
            max_number_of_properties = 20,
            property_types = [:Start],
            minimal_increase_property = 0.7,
            max_property_cost = 3,
            rule_cost_func = rule_cost_func,
        )

        append_result(path, result)
    end
end