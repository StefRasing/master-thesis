using HerbCore, HerbSearch, HerbConstraints, HerbSpecification, HerbBenchmarks, HerbGrammar
using JSON, MLStyle, DataStructures, Dates

include("utils/string_functions.jl")
include("utils/run_on_problem.jl")
include("../src/property_based_neighborhood_iterator.jl")

benchmark = HerbBenchmarks.PBE_SLIA_Track_2019
benchmark_name = "SyGuS strings"

# Remove problems containing "short", "long", "repeat" as they are duplicactes of other with different number of I/O examples
# univ problems have too many terminals to run in a descent amount of time...
problem_names = [String(s)[9:end] for s in names(benchmark; all=false) if startswith(String(s), "problem_") && all(f -> !occursin(f, String(s)), ["short", "long", "repeat", "univ"])]
timestamp = Dates.format(now(), "yyyy-mm-dd_HH:MM:SS")


# First perform a single run to let julia compile everything
for (i, n) in enumerate([problem_names[1]; problem_names])
    full_problem  = getfield(benchmark, Symbol("problem_", n))
    grammar = getfield(benchmark, Symbol("grammar_", n))

    if length(full_problem.spec) >= 10
        continue
    end

    property_grammar = deepcopy(grammar)
    merge_grammars!(property_grammar, @cfgrammar begin
        ntInt = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9
        ntBool = ntString == ntString
        ntBool = ntInt == ntInt
        ntBool = ntInt <= ntInt
        ntBool = ntInt < ntInt
    end)

    # Break symmetries a + b <> b + a and a == b <> b == a
    symmetric_rules = [rule isa Expr && rule.args[1] in [:+, :(==)] for  rule in property_grammar.rules]
    addconstraint!(property_grammar, Ordered(DomainRuleNode(symmetric_rules, [VarNode(:a), VarNode(:b)]), [:a, :b]))

    # Forbid if false/true then ... else ...
    if_rules = [rule isa Expr && rule.head in [:if] for rule in property_grammar.rules]
    true_false_rules = [rule in [true, false] for rule in property_grammar.rules]
    addconstraint!(property_grammar, Forbidden(DomainRuleNode(if_rules, [DomainRuleNode(true_false_rules, []), VarNode(:A), VarNode(:B)])))

    # Forbid if ... then S1 else S1
    addconstraint!(property_grammar, Forbidden(DomainRuleNode(if_rules, [VarNode(:A), VarNode(:B), VarNode(:B)])))

    # problem = Problem(full_problem.name, full_problem.spec[1:3])
    problem = full_problem

    results = run(
        benchmark = benchmark, 
        benchmark_name = benchmark_name,
        interpeter = interpret_sygus,
        problem = problem,
        full_problem = full_problem,
        grammar = grammar,
        property_grammar = property_grammar,
        property_symbol = :ntBool,
        pool_size = 5,
        max_extension_depth = 1,
        max_extension_size = 1,
        max_property_depth = 4,
        max_property_size = 6,
        max_number_of_properties = 5,
        max_iterations = typemax(Int),
        property_grammar_description = "Extensions: ints 0,1,2,3,4,5,6,7,8,9, == for String, ==, <=, < for Int. Constraints: a + b <> b + a, a == b <> b == a, forbid if true/false ..., forbid if ... then S else S. Prune properties that produce nothing on target outputs.",
    )

    println("$(i-1) of $(length(problem_names))")
    
    if i > 1
        save(results, timestamp)
    end
end
