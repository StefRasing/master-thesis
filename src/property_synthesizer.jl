
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

    interp = HerbInterpret.make_interpreter(grammar, target_module=benchmark, cache_module=benchmark)
    interp_one = (program, ys) -> [interp(program, (io.in[:_arg_out] = y; io.in)) for (io, y) in zip(problem.spec, ys)]
    interp_all = program -> [interp_one(program, ys) for ys in [[target_outputs]; local_optimum_outputs]]

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
        target_values = interp_one(property, target_outputs)
        score = sum(sum(interp_one(property, values) .!= target_values) for values in local_optimum_outputs)

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

    return best_property, ys -> sum(interp_one(best_property, ys) .!= best_target_values)
end