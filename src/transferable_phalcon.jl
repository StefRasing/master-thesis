
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

mutable struct StoredProperty
    repr::String
    property::Property
    property_grammar::AbstractGrammar
    property_interp
end

function StoredProperty(property::Property, property_grammar::AbstractGrammar)
    property_interpreter = HerbInterpret.make_interpreter(property_grammar, target_module=benchmark, cache_module=benchmark)
    property_interp = (program, io, y) -> property_interpreter(program, (new_in = copy(io.in); new_in[:_arg_out] = y; new_in))
    
    StoredProperty(
        string(rulenode2expr(property.program, property_grammar)),
        property,
        property_grammar,
        property_interp,
    )
end

Base.:(==)(a::StoredProperty, b::StoredProperty) = a.repr == b.repr

function transferable_phalcon(;
    iterator::ProgramIterator,
    stored_properties::Vector{StoredProperty},
    max_number_of_iterations::Int = typemax(Int),
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
    selected_stored_properties = []
    
    property_interpreter = HerbInterpret.make_interpreter(property_grammar, target_module=benchmark, cache_module=benchmark)
    property_interp = (program, io, y) -> property_interpreter(program, (new_in = copy(io.in); new_in[:_arg_out] = y; new_in))

    if !isnothing(selected_stored_properties)
        initial_cost(outputs_and_targets) = sum(
            sum(target_values .!= [stored_property.property_interp(stored_property.property.program, io, y) for (io, (y, _)) in zip(iterator.problem.spec, outputs_and_targets)])
            for (stored_property, target_values, _) in selected_stored_properties
        ; init=0)

        update_cost_function(iterator, initial_cost)
    end

    solution = nothing
    iterations = 0

    while time() - start < timeout
        iterations += 1

        # Run search and return if it found the solution
        solution = find_solution(iterator)
        !isnothing(solution) && break

        # Obtain local optimum
        outputs = local_optimum_outputs(iterator)

        #  Check if iteration limit is exceeded
        if iterations > max_number_of_iterations
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

        # Find library properties
        potential_stored_properties = []

        for stored_property in stored_properties
            target_values = [stored_property.property_interp(stored_property.property.program, io, io.out) for io in iterator.problem.spec]
            reduction_profile = [target_values != [stored_property.property_interp(stored_property.property.program, io, y) for (io, y) in zip(iterator.problem.spec, output)] for output in outputs]
            satisfied_indices = [i for (i, r) in enumerate(reduction_profile) if !r]
            reduction_number = sum(reduction_profile)
            reduction_rate = reduction_number / length(outputs)

            if reduction_rate >= 0.7 && reduction_rate < 1
                push!(potential_stored_properties, (stored_property, target_values, satisfied_indices, reduction_rate))
            end
        end

        invent_new_property = isempty(potential_stored_properties)
        sort!(potential_stored_properties, by = last, rev = true)
        outputs_to_satisfy = collect(1:length(outputs))

        while !isempty(potential_stored_properties)
            stored_property, target_values, satisfied_indices, reduction_rate = pop!(potential_stored_properties)
            isempty(intersect(satisfied_indices, outputs_to_satisfy)) && continue

            push!(selected_stored_properties, (stored_property, target_values, reduction_rate))
            setdiff!(outputs_to_satisfy, satisfied_indices)
        end

        # If none found, invent new property and add to library
        if invent_new_property
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

                repr = string(rulenode2expr(property.program, property_grammar))
                new_stored_property = StoredProperty(repr, property, property_grammar, property_interp)

                if !(new_stored_property in stored_properties)
                    push!(stored_properties, new_stored_property)
                end

                push!(selected_properties, property)
            end
        end

        # Define new cost
        cost(outputs_and_targets) = sum(
            sum(property.target_values .!= [property_interp(property.program, io, y) for (io, (y, _)) in zip(iterator.problem.spec, outputs_and_targets)])
            for property in selected_properties if !isnothing(property)
        ; init=0) + sum(
            sum(target_values .!= [stored_property.property_interp(stored_property.property.program, io, y) for (io, (y, _)) in zip(iterator.problem.spec, outputs_and_targets)])
            for (stored_property, target_values, _) in selected_stored_properties
        ; init=0)

        update_cost_function(iterator, cost)
    end

    return OrderedDict(
        "problem_name" => iterator.problem.name,
        "solved" => !isnothing(solution),
        "solution" => isnothing(solution) ? nothing : string(rulenode2expr(solution, iterator.solver.grammar)),
        "programs_enumerated" => iterator.programs_evaluated,
        "execution_time" => time() - start,
        "library_properties" => [
            (string(rulenode2expr(stored_property.property.program, stored_property.property_grammar)), reduction_rate)
            for (stored_property, _, reduction_rate) in selected_stored_properties],
        "heuristic" => [
            isnothing(property) ? "failed" : (string(rulenode2expr(property.program, property_grammar)), property.reduction_rate)
            for property in selected_properties],
        "population_costs" => population_costs,
    )
end