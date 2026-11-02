"""
    struct Individual

Store an Individual living in a population. Contains the program and the cost.
"""
struct Individual
    program::RuleNodeWithRuleCounts
    cost::Number
    parents::Union{Nothing, Individual, Tuple{Individual, Individual}}
    crossover::Union{Nothing,RuleNodeWithRuleCounts}
    crossover_parts::Union{Nothing,Tuple{RuleNodeWithRuleCounts, RuleNodeWithRuleCounts}}
    mutation::Union{Nothing,Symbol}
end

"""
    function Base.isless(a::Individual, b::Individual)

An Individual is less than another if it has a lower costs, breaking ties by chosing the smallest program.
"""
function Base.isless(a::Individual, b::Individual)
    a.cost != b.cost && return a.cost < b.cost
    return length(a.program) < length(b.program)
end

function Base.:(==)(a::Individual, b::Individual)
    a.cost == b.cost &&
    length(a.program) == length(b.program) &&
    a.program == b.program
end

