
function find_property!(;
    benchmark,
    problem,
    grammar::AbstractGrammar,
    local_optimum_outputs::Vector{Vector{Any}}, 
    minimal_increase::Float64, 
    maximum_increase::Float64,
    max_size::Int64,
)
    target_outputs = [io.out for io in problem.spec]

    interp = HerbInterpret.make_output_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
    specs = [(new_in = copy(io.in); new_in[:_arg_out] = y; new_in) for (io, y) in zip(Iterators.cycle(problem.spec), [target_outputs; local_optimum_outputs...])]
    interp_all = (rule, os) -> interp(rule, os, specs)

    max_score = sum(sum(output .!= target_outputs) for output in local_optimum_outputs)
    best_property = nothing
    best_score = -1
    best_target_values = nothing


    properties = CostBUSIterator(
        grammar, 
        :Start,
        max_size,
        Int64[1 for _ in grammar.rules],
        interp_all,
    )

    for property in properties
        all_values = property.outputs
        target_values = all_values[begin:length(problem.spec)]
        other_values = all_values[length(problem.spec)+1:end]

        score = sum(target_value != other_value for (target_value, other_value) in zip(Iterators.cycle(target_values), other_values))

        if score > max_score * maximum_increase
            continue
        end

        if score > best_score
            best_property = property
            best_score = score
            best_target_values = target_values
        end

        if score >= max_score * minimal_increase
            println("Shortcut")
            break
        end
    end

    interp = HerbInterpret.make_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
    interp_one = (program, io, y) -> interp(program, (io.in[:_arg_out] = y; io.in))
    program = RuleNode(best_property)

    return program, ys -> sum(best_target_values .!= [interp_one(program, io, y) for (io, y) in zip(problem.spec, ys)])
end