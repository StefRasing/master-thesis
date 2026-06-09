
function _grammar_to_property_grammar(grammar::AbstractGrammar)
    property_grammar = deepcopy(grammar)

    # Add 'y' rule for two cases
    if allequal(grammar.types)
        # 1. All rules are of the same type
        add_rule!(property_grammar, Expr(:(=), :Start, :_arg_out))
    else
        # 2. Rules have different types
        add_rule!(property_grammar, Expr(:(=), property_grammar.rules[1], :_arg_out))
    end

    # Add 'y' rule and constraint grammar to contain it
    addconstraint!(property_grammar, Contains(length(property_grammar.rules)))

    # Constraint grammar to contain it
    addconstraint!(property_grammar, Contains(length(property_grammar.rules)))

    return property_grammar
end

function run_with_timeout(f, timeout_seconds)
    task = @async f()

    start = time()
    while !istaskdone(task)
        if time() - start > timeout_seconds
            return nothing
        end
        sleep(0.1)
    end

    fetch(task)
end

#=
    Expects an iterator that implements at least the following:
        - function update_cost_function(iter::GeneticIterator, cost::Function)::Nothing
            change the cost function and change costs of current generation/pool

        - find_solution(iter::GeneticIterator)::Union{RuleNode,Nothing}
            drain the iterator until a solution is found, or return nothing

        - local_optimum_outputs(iter::GeneticIterator)::Vector{Vector{Any}}
            returns the outputs of programs in the last local optimum

=#

function phalcon(;
    iterator::ProgramIterator,
    max_number_of_properties::Int = typemax(Int),
    property_types::Vector,
    minimal_increase_property::Float64 = 0.8,
    max_property_cost::Int = 4,
    grammar_to_property_grammar::Function = _grammar_to_property_grammar,
    rule_costs::Vector{Int},
    timeout::Int = typemax(Int),
)
    start = time()
    previous_programs_evaluated = 0
    previous_time = start

    initialize!(iterator)
    property_grammar = grammar_to_property_grammar(iterator.solver.grammar)
    selected_properties = []
    solution = nothing

    run_with_timeout(timeout) do
        while true
            # Run search and return if it found the solution
            solution = find_solution(iterator)
            !isnothing(solution) && break

            # Obtain local optimum
            outputs = local_optimum_outputs(iterator)

            # Select new property if limit not exceeded
            if length(selected_properties) >= max_number_of_properties
                break
            end

            # Find new property
            property, partial_cost = find_property!(
                benchmark = iterator.benchmark,
                problem = iterator.problem,
                grammar = property_grammar,
                local_optimum_outputs = outputs, 
                property_types = property_types,
                minimal_increase = minimal_increase_property,
                max_depth = max_property_cost,
                rule_costs = rule_costs,
            )
            
            push!(selected_properties, (property, partial_cost))

            previous_programs_evaluated = iterator.programs_evaluated
            previous_time = time()

            # Define new cost
            cost(outputs_and_targets) = sum(partial_cost(map(first, outputs_and_targets)) for (property, partial_cost) in selected_properties)
            update_cost_function(iterator, cost)
        end
    end

    return OrderedDict(
        "problem_name" => iterator.problem.name,
        "solved" => !isnothing(solution),
        "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
        "programs_enumerated" => iterator.programs_evaluated,
        "programs_enumerated_last_iteration" => iterator.programs_evaluated - previous_programs_evaluated,
        "execution_time" => time() - start,
        "execution_time_last_iteration" => time() - previous_time,
        "heuristic" => [string(rulenode2expr(p, property_grammar)) for (p, _) in selected_properties],
    )
end