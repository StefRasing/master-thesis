
struct Property
    program::RuleNode
    target_values::Vector{Any}
end

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
    max_number_of_properties::Int = typemax(Int),
    property_types::Vector,
    minimal_increase_property::Float64 = 0.8,
    max_property_depth::Int = 4,
    grammar_to_property_grammar::Function = _grammar_to_property_grammar,
)
    initialize!(iterator)
    property_grammar = grammar_to_property_grammar(iterator.solver.grammar)
    selected_properties = []

    while true
        # Run search and return if it found the solution
        solution = find_solution(iterator)
        !isnothing(solution) && return solution, iterator.population[begin]

        # Obtain local optimum
        outputs = local_optimum_outputs(iterator)

        println("\n----[ Iteration $(length(selected_properties)+1) ]----")
        total_population_cost = sum(individual.cost for individual in iterator.population)
        @show total_population_cost
        println("\nBest individual:")
        for individual in iterator.population[1:1]
            expr = rulenode2expr(individual.program, grammar)
            cost = individual.cost

            @show expr
            @show cost
            benchmark.visualize(individual.program.outputs)
            println()
        end

        # for entry in iterator.population
        #     println(join(["\"" * string(o) * "\"" for o in entry.program.outputs], "\t"))
        # end

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
            property_types = property_types,
            minimal_increase = minimal_increase_property,
            max_depth = max_property_depth,
        )
        
        push!(selected_properties, (property, partial_cost))

        p = rulenode2expr(property, property_grammar)
        @show p

        # Define new cost
        cost(outputs_and_targets) = sum(partial_cost(map(first, outputs_and_targets)) for (property, partial_cost) in selected_properties)
        update_cost_function(iterator, cost)
    end

    return nothing, nothing
end