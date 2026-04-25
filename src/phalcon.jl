
struct Property
    program::RuleNode
    target_values::Vector{Any}
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
    grammar_to_property_grammar::Function = identity,
    # max_property_depth::Int = 4,
    # max_property_size::Int = 6,
    max_number_of_properties::Int = typemax(Int),
)
    target_outputs = [io.out for io in iterator.problem.spec]
    property_grammar = grammar_to_property_grammar(iterator.solver.grammar)
    selected_properties = []

    while true
        # Run search and return if it found the solution
        solution = find_solution(iterator)
        !isnothing(solution) && return solution

        # Obtain local optimum
        outputs = local_optimum_outputs(iterator)

        println("\n--------")

        for entry in iterator.population
            println(join(["\"" * o * "\"" for o in entry.program.outputs], "\t"))
        end

        # Select new property if limit not exceeded
        if length(selected_properties) >= max_number_of_properties
            break
        end

        # Find new property
        property, partial_cost = find_property!(
            benchmark = benchmark,
            problem = problem,
            grammar = property_grammar,
            local_optimum_outputs = outputs, 
            minimal_increase = 0.7, 
            maximum_increase = 0.9,
            max_size = 5
        )
        
        push!(selected_properties, (property, partial_cost))

        p = rulenode2expr(property, property_grammar)
        @show p

        # Define new cost
        cost(outputs_and_targets) = sum(partial_cost(map(first, outputs_and_targets)) for (property, partial_cost) in selected_properties)
        update_cost_function(iterator, cost)
    end

    return nothing
end