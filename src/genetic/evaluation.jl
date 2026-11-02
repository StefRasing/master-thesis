"""
    function outputs_to_cost(iter::GeneticIterator, outputs::Vector)

Given an GeneticIterator, maps a Vector of outputs to their cost. Basically is wrapper for the cost function that
ensures that programs that produce exceptions (return nothing) have Inf cost and programs that produce the target
outputs have a cost of -Inf.
"""
function outputs_to_cost(iter::GeneticIterator, outputs::Vector)
    # If any output is nothing, return +Inf
    any(isnothing, outputs) && return Inf

    # Obtain target outputs
    targets = [io.out for io in iter.problem.spec]

    # If problem is solved, return -Inf
    outputs == targets && return -Inf

    # Otherwise, call the provided cost function
    return iter.cost(zip(outputs, targets))
end

function interp(iter::GeneticIterator, rule_id::Int, children_outputs::AbstractVector)
    # Interp rule on outputs
    res = iter.interpreter(rule_id, children_outputs, iter.problem.spec)

    if iter.max_output_bytes != typemax(Int) && Base.summarysize(res) > iter.max_output_bytes
        return fill(nothing, length(iter.problem.spec))
    end

    # If program should be pruned by its output, return nothings
    !isnothing(iter.prune_node_by_output) && any(iter.prune_node_by_output(io, y) for (io, y) in zip(iter.problem.spec, res)) && return fill(nothing, length(iter.problem.spec))
    
    res
end

