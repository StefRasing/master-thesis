
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

    N = length(local_optimum_outputs)

    best_property = nothing
    best_reduction_number = 0
    best_target_values = nothing

    properties = LazyCostBasedBus(
        grammar, 
        property_types,
        max_cost,
        rule_costs,
        interp_all,
        prune_node_by_output,
    )

    information_differences = [0 for _ in 1:N]

    for property in properties
        all_values = property.outputs
        target_values = all_values[begin:length(problem.spec)]
        other_valuess = Iterators.partition(all_values[length(problem.spec)+1:end], length(problem.spec))

        equivalences = [other_values == target_values for other_values in other_valuess]
        sum(equivalences) == 0 && continue
        information_difference = -log2(sum(equivalences) / N)
        information_differences = information_differences .+ [equivalent ? 0 : information_difference for equivalent in equivalences]
        
        # any(other_values == target_values for (allowed, other_values) in zip(allowed_equivalences, other_valuess) if !allowed) && continue
        # reduction_number == N && continue

        # if reduction_number > best_reduction_number
        #     best_property = property
        #     best_target_values = target_values
        #     best_reduction_number = reduction_number

        #     if reduction_number == N - 1
        #         break
        #     end
        # end
    end

    i = argmin(information_differences)

    for property in properties
        all_values = property.outputs
        target_values = all_values[begin:length(problem.spec)]
        other_valuess = Iterators.partition(all_values[length(problem.spec)+1:end], length(problem.spec))

        equivalences = [other_values == target_values for other_values in other_valuess]

        if sum(equivalences) == 1 && equivalences[i]
            best_property = property
            best_target_values = target_values
            best_reduction_number = N - 1

            break
        end
    end


    for (out, diff) in zip(local_optimum_outputs, information_differences)
        println()
        @show out
        @show diff
    end

    if isnothing(best_property)
        return nothing
    end

    program = RuleNode(best_property)
    best_reduction_rate = best_reduction_number / length(local_optimum_outputs)

    return Property(program, best_target_values, best_reduction_rate)
end