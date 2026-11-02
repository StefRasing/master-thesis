"""
    function find_solution(iter::GeneticIterator; deadline::Real = Inf)::Union{RuleNode,Nothing}

Function needed by the Phalcon interface. Attempts to find a solution. Terminates if the total cost of the
population hasn't improvded for N generation (max_generations_without_improvement).

Returns a solution as RuleNode, or nothing if search failed.
"""
function find_solution(iter::GeneticIterator; deadline::Real = Inf)::Union{RuleNode,Nothing}
    _check_deadline(deadline)
    if !isempty(iter.population) && iter.population[begin].cost == -Inf
        return RuleNode(iter.population[begin].program)
    end

    # Count number of stable populations and store the last seen cost
    stable_populations = 0
    population_cost = sum(individual.cost for individual in iter.population)
    iterations = 0

    # Loop until stability critereon has been met
    while stable_populations < iter.max_generations_without_improvement
        combine!(iter; deadline=deadline)
        iterations += 1

        # Cost if -Inf means a solution has been found. In that case convert program to RuleNode and return.
        if iter.population[begin].cost == -Inf
            return RuleNode(iter.population[begin].program)
        end

        # If the new_population_cost is the same as before, increment stable_populations, otherwise reset it
        new_population_cost = sum(individual.cost for individual in iter.population)
        stable_populations = new_population_cost == population_cost ? stable_populations + 1 : 0
        population_cost = new_population_cost

        new_population_cost == 0 && return nothing
    end

    # Search failed, return nothing.
    return nothing
end

"""
    local_optimum_outputs(iter::GeneticIterator)::Vector

Function needed by the Phalcon interface. Returns the outputs of the current local optimum, which is the
population in the case of genetic search.
"""
local_optimum_outputs(iter::GeneticIterator)::Vector = [individual.program.outputs for individual in iter.population]

"""
    function combine!(iter::GeneticIterator; deadline::Real = Inf)::Nothing

Creates a new generation by creating M (candidate_pool_size) new individuals and selecting the N best ones:
    - Select two random parents 1 and 2
    - Create four individuals:
        1. Mutate parent 1
        2. Mutate parent 2
        3. Crossover parent 1 and 2
        4. Mutate individual 3
"""
function combine!(iter::GeneticIterator; deadline::Real = Inf)::Nothing
    # It does not make sense to select parents with size 1 as that will always create an already existing extension
    selection_pool = [ind for ind in iter.population if length(ind.program) > 1]
    
    isempty(selection_pool) && throw(ArgumentError("Cannot select genetic parents: selection pool is empty (population contains no programs larger than one node)"))

    # Create candidates
    for _ in 1:4:iter.candidate_pool_size
        _check_deadline(deadline)
        # Select parents using tournament selection
        parent_1 = rand(iter.rng, selection_pool)
        parent_2 = rand(iter.rng, selection_pool)
        program_1 = parent_1.program
        program_2 = parent_2.program

        # Crossover and mutate
        child_1, mutation_1 = mutate(iter, program_1)
        _check_deadline(deadline)
        child_2, mutation_2 = mutate(iter, program_2)
        _check_deadline(deadline)
        child_3, crossover_parts = crossover(iter, program_1, program_2)
        _check_deadline(deadline)
        child_4, mutation_4 = mutate(iter, child_3)

        # Create individuals
        individual_1 = Individual(iter, child_1, parent_1, mutation_1)
        individual_2 = Individual(iter, child_2, parent_2, mutation_2)
        individual_3 = Individual(iter, child_3, (parent_1, parent_2), child_3, crossover_parts, :none)
        individual_4 = Individual(iter, child_4, (parent_1, parent_2), child_3, crossover_parts, mutation_4)
        
        # Add both to population
        add_to_population!(iter, individual_1)
        add_to_population!(iter, individual_2)
        add_to_population!(iter, individual_3)
        add_to_population!(iter, individual_4)

        iter.population[begin].cost == -Inf && return nothing
        length(iter.population) == iter.population_size && iter.population[end].cost == 0 && return nothing
    end

    return nothing
end


"""
    mutable struct GeneticIteratorState

Contains the current queue of Individual's and a list of past_population_costs to check for the termination critereon.
"""
mutable struct GeneticIteratorState
    queue::Vector{Individual}
    past_population_costs::Vector{Number}
end

"""
    GeneticIteratorState()

Creates an empty GeneticIteratorState.
"""
GeneticIteratorState() = GeneticIteratorState(Individual[], Number[])

"""
    function add_new_population!(state::GeneticIteratorState, population::Vector{Individual})::Nothing

Alters a given GeneticIteratorState after a new population has been combined. Automatically updates queue
and the past_population_costs vector.
"""
function add_new_population!(state::GeneticIteratorState, population::Vector{Individual})::Nothing
    total_cost = sum(Number[individual.cost for individual in population])
    state.queue = copy(population)
    push!(state.past_population_costs, total_cost)
    return nothing
end


function Base.iterate(iter::GeneticIterator)
    initialize!(iter)

    # Initialize iterator state and start iterating
    state = GeneticIteratorState()
    add_new_population!(state, iter.population)

    return Base.iterate(iter, state)
end

function Base.iterate(iter::GeneticIterator, state::GeneticIteratorState)
    if isempty(state.queue)
        # If the last n generations had constant cost, terminate search
        n = iter.max_generations_without_improvement
        if length(state.past_population_costs) >= n && allequal(state.past_population_costs[end-n+1:end])
            return nothing
        end

        # Otherwise, create new population and add to state
        combine!(iter)
        add_new_population!(state, iter.population)
    end

    # Return program of first queue item and state
    return popfirst!(state.queue).program, state
end
