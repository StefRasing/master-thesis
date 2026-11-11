_has_batch_parents(iterator) = any(ind -> length(ind.program) > 1, iterator.population)

# A flat initial cost makes ordinary search stop even with an undersized
# population. For sampling, continue while the pool grows or until it stalls.
function _fill_batch_population!(iterator; deadline)
    stagnant = 0
    while true
        _check_deadline(deadline)
        population = iterator.population
        if !isempty(population) && first(population).cost == -Inf
            return RuleNode(first(population).program)
        end
        size = length(population)
        size >= iterator.population_size && return nothing
        stagnant >= iterator.max_generations_without_improvement && return nothing
        _has_batch_parents(iterator) || return nothing

        combine!(iterator; deadline)
        stagnant = length(population) == size ? stagnant + 1 : 0
    end
end

function _unique_batch_properties(; problem, deadline, kwargs...)
    candidates = Property[]
    seen_agreements = Set{BitVector}()
    properties = _property_candidates(; problem, deadline, kwargs...)
    for property in properties
        _check_deadline(deadline)
        target_values, local_values = _property_values(property, length(problem.spec))
        pattern = BitVector(values == target_values for values in local_values)
        agreement = count(pattern)
        agreement > 0 || continue
        pattern in seen_agreements && continue
        push!(seen_agreements, pattern)
        index = _property_enumeration_index(properties)
        push!(candidates, Property(RuleNode(property), target_values, agreement, index))
    end
    return candidates
end

"""
    phalcon_batch(; iterator, max_number_of_properties=20, ...)

Collect up to `max_number_of_properties * iterator.population_size` distinct
program output vectors in one initial search. Enumerate properties once and
keep the first property for each distinct, nonempty agreement pattern on
the full sample. Select in order of increasing agreement count, breaking
ties by enumeration order.
`max_property_evaluations` defaults to 10,000 for the batch property search.
Install the sum of all selected properties as the cost for one guided search
at the original population size. All phases share a cooperative deadline.

`agreement_threshold` is accepted for compatibility with shared Phalcon
options. Batch Phalcon always ranks by the full agreement count.
"""
function phalcon_batch(;
    iterator::GeneticIterator,
    max_number_of_properties::Int = 20,
    property_types::Vector,
    max_property_cost::Union{Nothing,Int} = nothing,
    max_property_evaluations::Int = isnothing(max_property_cost) ? DEFAULT_MAX_PROPERTY_EVALUATIONS : typemax(Int),
    agreement_threshold::Int = 1,
    grammar_to_property_grammar::Function = _grammar_to_property_grammar,
    rule_cost_func::Function,
    prune_node_by_output::Function = _ -> false,
    max_output_bytes::Int = typemax(Int),
    timeout::Real = typemax(Int),
    verbose::Bool = false,
    display_outputs::Function = println,
)
    max_number_of_properties > 0 || throw(ArgumentError("max_number_of_properties must be positive"))
    agreement_threshold >= 1 || throw(ArgumentError("agreement_threshold must be positive"))
    max_property_evaluations >= 0 || throw(ArgumentError("max_property_evaluations must be nonnegative"))
    population_size = iterator.population_size
    population_size > 0 || throw(ArgumentError("population_size must be positive"))
    sample_target = Base.Checked.checked_mul(max_number_of_properties, population_size)
    start = time()
    deadline = _search_time() + timeout
    properties_enumerated = Ref(0)
    selected_properties = Property[]
    population_costs = Number[]
    program_synthesis_durations = Float64[]
    property_invention_durations = Float64[]
    solution = nothing
    property_grammar = nothing
    sample_size = 0

    try
        iterator.population_size = sample_target
        outputs = try
            initialize!(iterator; deadline)
            solution = _fill_batch_population!(iterator; deadline)
            sample_size = length(iterator.population)
            local_optimum_outputs(iterator)
        finally
            iterator.population_size = population_size
            resize!(iterator.population, min(population_size, length(iterator.population)))
        end
        push!(program_synthesis_durations, time() - start)

        if isnothing(solution) && !isempty(outputs) && max_property_evaluations > 0
            _check_deadline(deadline)
            push!(population_costs, sum(ind.cost for ind in iterator.population))
            if verbose
                @show sample_size sample_target
                best = first(iterator.population)
                @show rulenode2expr(best.program, iterator.solver.grammar) best.cost
                display_outputs(best.program.outputs)
            end

            start_time = time()
            property_grammar = grammar_to_property_grammar(iterator.solver.grammar)
            rule_costs = Int[rule_cost_func(r) for r in property_grammar.rules]
            try
                candidates = _unique_batch_properties(;
                    benchmark=iterator.benchmark, problem=iterator.problem,
                    grammar=property_grammar, local_optimum_outputs=outputs,
                    property_types, max_cost=max_property_cost, max_property_evaluations, rule_costs,
                    prune_node_by_output, max_output_bytes, deadline, properties_enumerated)
                sort!(candidates; by=property -> property.agreement)
                _check_deadline(deadline)
                selected_properties = resize!(candidates, min(max_number_of_properties, length(candidates)))
                if verbose
                    for property in selected_properties
                        @show rulenode2expr(property.program, property_grammar) property.target_values property.agreement
                    end
                end
            finally
                push!(property_invention_durations, time() - start_time)
            end
        end

        if !isempty(selected_properties)
            _check_deadline(deadline)
            interpreter = HerbInterpret.make_interpreter(property_grammar;
                target_module=iterator.benchmark, cache_module=iterator.benchmark)
            property_interp = (program, io, y) -> interpreter(program, (new_in = copy(io.in); new_in[:_arg_out] = y; new_in))
            start_time = time()
            update_cost_function(iterator, _property_cost(iterator.problem, selected_properties, property_interp); deadline)
            if !isempty(iterator.population) && (first(iterator.population).cost == -Inf || _has_batch_parents(iterator))
                solution = find_solution(iterator; deadline)
            end
            push!(program_synthesis_durations, time() - start_time)
        end
    catch err
        err isa SearchTimeout || rethrow()
    end

    stats = _phalcon_stats(iterator, solution, start, properties_enumerated[],
        property_grammar, selected_properties, population_costs,
        program_synthesis_durations, property_invention_durations)
    stats["property_sample_target"] = sample_target
    stats["property_sample_size"] = sample_size
    return solution, stats
end
