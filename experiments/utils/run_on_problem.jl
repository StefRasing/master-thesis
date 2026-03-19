function run(;
    benchmark,
    benchmark_name,
    interpeter,
    problem,
    full_problem,
    grammar,
    starting_symbol = nothing,
    property_grammar,
    property_symbol,
    pool_size = 10,
    max_extension_depth = 1,
    max_extension_size = 1,
    max_property_depth = 4,
    max_property_size = 6,
    max_number_of_properties = 50,
    max_iterations = 10000,
    property_grammar_description = "",
)
    original_problem = deepcopy(full_problem)

    stats = @timed begin
        starting_symbol = isnothing(starting_symbol) ? grammar.rules[1] : starting_symbol
        add_rule!(property_grammar, Expr(:(=), starting_symbol, :_arg_out))
        addconstraint!(property_grammar, Contains(length(property_grammar.rules)))
        grammar_tags = get_relevant_tags(property_grammar)

        properties = Vector{AbstractRuleNode}(collect(BFSIterator(property_grammar, property_symbol, 
            max_depth = max_property_depth, 
            max_size = max_property_size,
        )))

        properties_with_target_values = Tuple{AbstractRuleNode, Any}[]
        for p in properties
            values = [interpret_sygus(p, grammar_tags, (io.in[:_arg_out] = io.out; io.in)) for io in problem.spec]

            if !any(isnothing, values)
                push!(properties_with_target_values, (p, values))
            end
        end

        number_of_candidate_properties = length(properties_with_target_values)

        iterator = PropertyBasedNeighborhoodIterator(grammar, starting_symbol,
            problem,
            (p, x) -> interpret_sygus(p, grammar_tags, x),
            pool_size,
            properties_with_target_values,

            max_extension_depth = max_extension_depth,
            max_extension_size = max_extension_size,

            property_grammar = property_grammar,

            max_number_of_properties = max_number_of_properties,
        )

        iterations = nothing
        solution = nothing
        full_problem_acc = nothing
        solution_entry = nothing

        function path_to_solution(pool_entry)
            if isnothing(pool_entry.parent)
                return []
            end

            (p, i) = pool_entry.parent
            c = p.cost
            entry = (p.program, c, i)
            
            return [path_to_solution(p); entry]
        end

        for (i, program) in enumerate(iterator)
            cost = heuristic_cost(iterator, program)
            expr = rulenode2expr(program, grammar)
            pool_entry = iterator.pool[findfirst(e -> e.program == program, iterator.pool)]
            
            # println()
            # @show i
            # @show expr
            # @show program._val
            # @show cost
            # for (e, c, i) in path_to_solution(pool_entry)
            #     println("$i\t$c\t$e")
            # end

            if program._val == [io.out for io in problem.spec]
                iterations = i
                solution = program
                solution_entry = pool_entry
                full_problem_acc = count(interpeter(program, grammar_tags, io.in) == io.out for io in full_problem.spec)
                # println()
                # @show i
                # @show expr
                # @show program._val
                # @show cost
                # for (e, c, i) in path_to_solution(pool_entry)
                #     println("$i\t$c\t$e")
                # end
                break
            end

            if i == max_iterations
                iterations = i
                break
            end
        end
    end

    # println("\nProblem $(problem.name)")
    # for io in original_problem.spec
    #     println("$(io.in) -> $(io.out)")
    # end

    # if isnothing(solution)
    #     println("\nReached max iterations or properties")
    # else
    #     println("\nSolution found in $iterations iterations!")
    #     expr = rulenode2expr(solution, grammar)
    #     @show expr

    #     full_problem_acc = count(interpeter(solution, grammar_tags, io.in) == io.out for io in full_problem.spec)
    #     println("Solved $full_problem_acc / $(length(full_problem.spec)) (trained on $(length(problem.spec)))")
    # end

    # println("\nEvaluated $(iterator.programs_evaluated[]) programs")
    # println("\nRan for $(stats.time) seconds")

    # println("\nWith $(length(iterator.selected_properties)) properties:")
    # for (property, target_values) in iterator.selected_properties
    #     prop = rulenode2expr(property, property_grammar)
    #     println(" - $target_values \t $prop")
    # end

    base_synthesizer_description = "Neighborhood search. Neighborhood is obtained by expanding all pool entries. To expand a pool entry, each node in the program is replaced with a grammar rule, filled with an extension or the program (exactly in one place)."

    return OrderedDict(
        "specification" => OrderedDict(
            "benchmark_name" => benchmark_name,
            "problem" => original_problem,
            "training_examples" => length(problem.spec),
            "total_examples" => length(full_problem.spec),
            "timestamp" => Dates.format(now(), "yyyy-mm-dd at HH:MM:SS"),
        ),
        "hyperparameters" => OrderedDict(
            "pool_size" => pool_size,
            "max_extension_depth" => max_extension_depth,
            "max_extension_size" => max_extension_size,
            "max_property_depth" => max_property_depth,
            "max_property_size" => max_property_size,
            "max_number_of_properties" => max_number_of_properties,
            "max_iterations" => max_iterations,
            "property_grammar_description" => property_grammar_description,
            "base_synthesizer_description" => base_synthesizer_description
        ),
        "solution" => isnothing(solution) ? nothing : OrderedDict(
            "rulenode" => string(solution),
            "expression" => string(rulenode2expr(solution, grammar)),
            "depth" => depth(solution),
            "size" => length(solution),
            "solved_examples" => full_problem_acc,
            "path_to_solution" => [OrderedDict(
                "rulenode" => string(p),
                "expression" => string(rulenode2expr(p, grammar)), 
                "cost" => c, 
                "index_in_pool" => i) for (p, c, i) in [path_to_solution(solution_entry); (solution, solution_entry.cost, 1)]],
        ),
        "statistics" => OrderedDict(
            "programs_evaluated" => iterator.programs_evaluated[],
            "execution_time_seconds" => stats.time,
            "memory_bytes" => stats.bytes,
        ),
        "heuristic" => OrderedDict(
            "number_of_candidate_properties" => number_of_candidate_properties,
            "selected_properties" => length(iterator.selected_properties),
            "properties" => [OrderedDict(
                "rulenode" => string(p), 
                "expression" => string(rulenode2expr(p, property_grammar)), 
                "target_values" => string(v), 
                "iteration_added" => i) 
                for (i, (p, v)) in enumerate(iterator.selected_properties)],
        ),
    )
end

function save(results, timestamp)
    benchmark_name = results["specification"]["benchmark_name"]
    pool_size = first(results["hyperparameters"]["pool_size"])
    filename = "data/$(benchmark_name)-$(timestamp)-pool_size=$pool_size.json"
    data = isfile(filename) ? JSON.parsefile(filename) : Any[]
    push!(data, results)

    open(filename, "w") do io
        JSON.print(io, data, 4)
    end
end
