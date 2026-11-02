
struct Property
    program::AbstractRuleNode
    target_values::Vector
    reduction_rate::Number
end

function find_property!(;
    benchmark,
    problem,
    grammar::AbstractGrammar,
    local_optimum_outputs::AbstractVector{<:AbstractVector},
    property_types::Vector{Symbol},
    max_cost::Int64,
    rule_costs::Vector{Int},
    prune_node_by_output::Function = _ -> false,
    max_output_bytes::Int = 21 * 1024^2,
    deadline::Real = Inf,
    stop_reduction_rate::Union{Nothing,Real} = nothing,
)
    isnothing(stop_reduction_rate) || 0 < stop_reduction_rate < 1 ||
        throw(ArgumentError("stop_reduction_rate must be between 0 and 1"))
    _check_deadline(deadline)
    target_outputs = [io.out for io in problem.spec]

    interp = HerbInterpret.make_output_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
    specs = [(new_in = copy(io.in); new_in[:_arg_out] = y; new_in) for (io, y) in zip(Iterators.cycle(problem.spec), [target_outputs; local_optimum_outputs...])]
    interp_all = (rule, os) -> interp(rule, os, specs)

    best_property = nothing
    best_reduction_number = 0
    best_target_values = nothing
    maximum_reduction_number = isnothing(stop_reduction_rate) ?
        length(local_optimum_outputs) - 1 : ceil(Int, stop_reduction_rate * length(local_optimum_outputs))

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
        other_valuess = Iterators.partition(all_values[length(problem.spec)+1:end], length(problem.spec))

        reduction_number = count(other_values != target_values for other_values in other_valuess)

        if reduction_number != length(local_optimum_outputs) && reduction_number > best_reduction_number
            best_property = property
            best_target_values = target_values
            best_reduction_number = reduction_number

            if reduction_number >= maximum_reduction_number
                break
            end
        end
    end

    if isnothing(best_property)
        return nothing
    end

    program = RuleNode(best_property)
    best_reduction_rate = best_reduction_number / length(local_optimum_outputs)

    return Property(program, best_target_values, best_reduction_rate)
end
