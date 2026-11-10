
struct Property
    program::AbstractRuleNode
    target_values::Vector
    agreement::Int
end

"""Find a property using fresh task outputs and enumeration state on every call.

An optional `interpreter` may be reused only for the same unchanged grammar and
benchmark module. It caches generated code, not inputs, outputs or search state.
"""
function find_property!(;
    benchmark,
    problem,
    grammar::AbstractGrammar,
    local_optimum_outputs::AbstractVector{<:AbstractVector},
    property_types::Vector{Symbol},
    max_cost::Int64,
    rule_costs::Vector{Int},
    interpreter = nothing,
    prune_node_by_output::Function = _ -> false,
    max_output_bytes::Int = 21 * 1024^2,
    deadline::Real = Inf,
    # Shared across property searches; updated before interpretation, including pruned candidates.
    properties_enumerated::Base.RefValue{Int} = Ref(0),
)
    _check_deadline(deadline)
    target_outputs = [io.out for io in problem.spec]

    interp = isnothing(interpreter) ?
        HerbInterpret.make_output_interpreter(grammar, target_module=benchmark, cache_module=benchmark) : interpreter
    specs = [(new_in = copy(io.in); new_in[:_arg_out] = y; new_in) for (io, y) in zip(Iterators.cycle(problem.spec), [target_outputs; local_optimum_outputs...])]
    interp_all = (rule, os) -> begin
        properties_enumerated[] += 1
        interp(rule, os, specs)
    end

    best_property = nothing
    best_target_values = nothing
    best_agreement = length(local_optimum_outputs)

    properties = LazyCostBasedBus(
        grammar, 
        property_types,
        max_cost,
        rule_costs,
        interp_all,
        prune_node_by_output;
        max_output_bytes = max_output_bytes,
        deadline = deadline,
    )

    for property in properties
        _check_deadline(deadline)
        all_values = property.outputs
        target_values = all_values[begin:length(problem.spec)]
        local_property_values = Iterators.partition(all_values[length(problem.spec)+1:end], length(problem.spec))

        agreement = count(values == target_values for values in local_property_values)

        if agreement > 0
            best_property = property
            best_target_values = target_values
            best_agreement = agreement

            agreement == 1 && break
        end
    end

    if isnothing(best_property)
        return nothing
    end

    program = RuleNode(best_property)

    return Property(program, best_target_values, best_agreement)
end
