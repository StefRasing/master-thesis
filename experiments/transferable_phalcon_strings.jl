using Pkg
Pkg.activate("../master-thesis")
Pkg.instantiate()
Pkg.precompile()

using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using StatsBase, RuntimeGeneratedFunctions, DataStructures, SparseArrays, JSON3, JLD2, Random

include("io.jl")
include("../src/lazy_cost_based_bus.jl")
include("../src/genetic_iterator.jl")
include("../src/property_synthesizer_playground.jl")
include("../src/transferable_phalcon.jl")

repetitions = 1
run = ARGS[1]
# path =          "data/transferable_phalcon_strings/transferable_phalcon_strings$(run).json"
# property_path = "data/transferable_phalcon_strings/properties/properties$(run).jld2"
path =          "data/strict_transferable_phalcon_strings/strict_transferable_phalcon_strings$(run).json"
property_path = "data/strict_transferable_phalcon_strings/properties/properties$(run).jld2"
store = true

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
RuntimeGeneratedFunctions.init(benchmark)

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# Results in 124 problems
task_names = [String(s)[9:end] for s in names(benchmark; all=true) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "small"])]
task_names = shuffle(MersenneTwister(run), task_names)

problems = [getfield(benchmark, Symbol("problem_", name)) for name in task_names]
grammars = [getfield(benchmark, Symbol("grammar_", name)) for name in task_names]

string_to_string_tasks = ["problem_11440431", "problem_11604909", "problem_17212077", "problem_2171308", "problem_25239569", "problem_28627624_1", "problem_30732554", "problem_31753108", "problem_33619752", "problem_34801680", "problem_35744094", "problem_36462127", "problem_38664547", "problem_38871714", "problem_39060015", "problem_41503046", "problem_43120683", "problem_43606446", "problem_bikes", "problem_change_negative_numbers_to_positive", "problem_clean_and_reformat_telephone_numbers", "problem_dr_name", "problem_exceljet2", "problem_exceljet3", "problem_exceljet4", "problem_extract_word_containing_specific_text", "problem_extract_word_that_begins_with_specific_character", "problem_firstname", "problem_get_domain_name_from_url", "problem_get_first_name_from_name", "problem_get_first_word", "problem_get_last_line_in_cell", "problem_get_last_name_from_name", "problem_get_last_name_from_name_with_comma", "problem_get_last_word", "problem_get_middle_name_from_full_name", "problem_initials", "problem_lastname", "problem_phone", "problem_phone_1", "problem_phone_10", "problem_phone_2", "problem_phone_3", "problem_phone_4", "problem_phone_5", "problem_phone_6", "problem_phone_7", "problem_phone_8", "problem_phone_9", "problem_remove_file_extension_from_filename", "problem_remove_leading_and_trailing_spaces_from_text", "problem_remove_text_by_matching", "problem_remove_text_by_position", "problem_replace_one_character_with_another", "problem_stackoverflow1", "problem_stackoverflow10", "problem_stackoverflow11", "problem_stackoverflow2", "problem_stackoverflow3", "problem_stackoverflow4", "problem_stackoverflow5", "problem_stackoverflow6", "problem_stackoverflow8", "problem_stackoverflow9", "problem_strip_html_from_text_or_numbers", "problem_strip_non_numeric_characters", "problem_strip_numeric_characters_from_cell"]

stored_properties = load_properties(property_path)

for (problem, grammar) in zip(problems, grammars)
    !(problem.name in string_to_string_tasks) && continue
    performed_repetitions(path, problem.name) > 0 && continue

    max_length = 2 * maximum([max(maximum(length, values(io.in)), length(io.out)) for io in problem.spec])
    rule_cost_func = r -> r isa Expr
    rule_costs = Int[rule_cost_func(rule) for rule in grammar.rules]

    iterator = GeneticIterator(grammar, :Start,
        benchmark = benchmark,
        problem = problem,
        cost = _ -> 0,
        population_size = 20,
        candidate_pool_size = 2000,
        max_generations_without_improvement = 10,
        max_extension_size = 1,
        max_initial_population_size = 1,
        max_size = 50,
        rule_costs = rule_costs,
        prune_node_by_output = (io, y) -> length(y) > max_length,
    )

    result = transferable_phalcon(
        iterator = iterator,
        stored_properties = stored_properties,
        max_number_of_iterations = 20,
        property_types = [:ntString, :ntInt, :ntBool],
        max_property_cost = 3,
        rule_cost_func = rule_cost_func,
        prune_node_by_output = y -> length(y) > max_length,
        verbose = false,
        timeout = 60*30,
    )

    if store
        append_result(path, result)
        store_properties(property_path, stored_properties)
    else
        println()
        @show result
    end
end
