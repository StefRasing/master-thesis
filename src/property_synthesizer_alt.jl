
struct Property
    program::AbstractRuleNode
    target_values::Vector{Any}
    reduction_rate::Number
end

function find_property!(;
    benchmark,
    problem,
    grammar::AbstractGrammar,
    local_optimum_outputs::Vector{Vector{Any}}, 
    property_types::Vector{Symbol},
    max_cost::Int64,
    rule_costs::Vector{Int},
    prune_node_by_output::Function,
)
    target_outputs = [io.out for io in problem.spec]

    interp = HerbInterpret.make_output_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
    specs = [(new_in = copy(io.in); new_in[:_arg_out] = y; new_in) for (io, y) in zip(Iterators.cycle(problem.spec), [target_outputs; local_optimum_outputs...])]
    interp_all = (rule, os) -> interp(rule, os, specs)

    best_property = nothing
    best_reduction_number = 0
    best_target_values = nothing
    maximum_reduction_number = length(local_optimum_outputs) - 1

    properties = LazyCostBasedBus(
        grammar, 
        property_types,
        max_cost,
        rule_costs,
        interp_all,
        prune_node_by_output,
    )

    for property in properties
        all_values = property.outputs
        target_values = all_values[begin:length(problem.spec)]
        other_valuess = Iterators.partition(all_values[length(problem.spec)+1:end], length(problem.spec))

        reduction_number = count(other_values != target_values for other_values in other_valuess)

        if reduction_number != length(local_optimum_outputs) && reduction_number > best_reduction_number
            best_property = property
            best_target_values = target_values
            best_reduction_number = reduction_number

            if reduction_number >= length(local_optimum_outputs) * 0.9
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