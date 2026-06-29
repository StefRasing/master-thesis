
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
    max_property_cost::Int,
    grammar_to_property_grammar::Function = _grammar_to_property_grammar,
    rule_cost_func::Function,
    prune_node_by_output::Function = _ -> false,
    timeout::Int = typemax(Int),
    verbose::Bool = false,
)
    start = time()
    population_costs = []

    initialize!(iterator)

    property_grammar = grammar_to_property_grammar(iterator.solver.grammar)
    rule_costs = Int[rule_cost_func(r) for r in property_grammar.rules]
    selected_properties = []
    
    property_interpreter = HerbInterpret.make_interpreter(property_grammar, target_module=benchmark, cache_module=benchmark)
    property_interp = (program, io, y) -> property_interpreter(program, (new_in = copy(io.in); new_in[:_arg_out] = y; new_in))

    solution = nothing

    while time() - start < timeout
        # Run search and return if it found the solution
        solution = find_solution(iterator)
        !isnothing(solution) && break

        # Obtain local optimum
        outputs = local_optimum_outputs(iterator)

        # Select new property if limit not exceeded
        if length(selected_properties) >= max_number_of_properties
            break
        end

        population_cost = sum(ind.cost for ind in iterator.population)
        push!(population_costs, population_cost)

        if verbose
            best = iterator.population[begin]
            expr = rulenode2expr(best.program, iterator.solver.grammar)
            cost = best.cost
            out = best.program.outputs

            println()
            @show population_cost
            @show expr
            @show cost

            if iterator.benchmark == HerbBenchmarks.ARC_AGI1
                HerbBenchmarks.ARC_AGI1.visualize(out)
            else
                @show out
            end
        end

        # Find new property
        property = find_property!(
            benchmark = iterator.benchmark,
            problem = iterator.problem,
            grammar = property_grammar,
            local_optimum_outputs = outputs, 
            property_types = property_types,
            max_cost = max_property_cost,
            rule_costs = rule_costs,
            prune_node_by_output = prune_node_by_output,
        )

        if isnothing(property)
            if verbose
                println("Failed to find property...")
            end
        else
            if verbose
                expr = rulenode2expr(property.program, property_grammar)

                println()
                @show expr
                @show property.target_values
                @show property.reduction_rate
            end
        end

        push!(selected_properties, property)

        # Define new cost
        cost(outputs_and_targets) = sum(
            sum(property.target_values .!= [property_interp(property.program, io, y) for (io, (y, _)) in zip(iterator.problem.spec, outputs_and_targets)])
            for property in selected_properties if !isnothing(property)
        , init=0)

        update_cost_function(iterator, cost)
    end

    return OrderedDict(
        "problem_name" => iterator.problem.name,
        "solved" => !isnothing(solution),
        "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
        "programs_enumerated" => iterator.programs_evaluated,
        "execution_time" => time() - start,
        "heuristic" => [
            isnothing(property) ? "failed" : (string(rulenode2expr(property.program, property_grammar)), property.reduction_rate)
            for property in selected_properties],
        "population_costs" => population_costs,
    )
end