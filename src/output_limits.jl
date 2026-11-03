# Fast acceptance against the existing Base.summarysize limit. Overcounting is
# safe here: an inconclusive bound always falls back to the original traversal.
# The array layout and Memory charging below match Julia 1.12's summarysize.jl;
# other Julia versions retain the general check until their layout is validated.
const _FAST_OUTPUT_BOUND = VERSION.major == 1 && VERSION.minor == 12
const _OUTPUT_BOUND_WORK = 1024
const _OUTPUT_BOUND_DEPTH = 8

@inline function _output_size_budget(@nospecialize(value), bytes::Int, work::Int, depth::Int)::Tuple{Int,Int}
    work > 0 || return (-1, 0)
    # Includes Int, UInt64 (the bitvector DSL), Bool, CartesianIndex{2}, and
    # Tuple{Int,CartesianIndex{2}}. Pointer-free immutable values retain nothing
    # beyond their inline payload. Other values (notably captured functions,
    # BigInt, views and SubString) use summarysize's general graph traversal.
    isbitstype(typeof(value)) || return (-1, 0)
    size = Core.sizeof(value)
    size <= bytes || return (-1, 0)
    return (bytes - size, work - 1)
end

@inline function _output_size_budget(value::String, bytes::Int, work::Int, depth::Int)::Tuple{Int,Int}
    work > 0 || return (-1, 0)
    sizeof(Int) <= bytes || return (-1, 0)
    bytes -= sizeof(Int)
    size = Core.sizeof(value)
    size <= bytes || return (-1, 0)
    return (bytes - size, work - 1)
end

function _output_size_budget(value::Array{T}, bytes::Int, work::Int, depth::Int)::Tuple{Int,Int} where {T}
    work > 0 && depth > 0 || return (-1, 0)
    work -= 1
    # Core.sizeof charges the Array descriptor, not its logical element size.
    # Follow the full Memory, not just visible elements: pop!, sizehint! and
    # reshaping can retain storage/references outside the visible array range.
    memory = getfield(getfield(value, :ref), :mem)
    header = Core.sizeof(value)
    header <= bytes || return (-1, 0)
    bytes -= header
    header = 2 * sizeof(Int) # GenericMemory descriptor, as in Base.summarysize
    header <= bytes || return (-1, 0)
    bytes -= header
    payload = sizeof(memory) # Includes capacity and isbits-union tag bytes.
    payload <= bytes || return (-1, 0)
    bytes -= payload
    (isbitstype(T) || Base.isbitsunion(T)) && return (bytes, work)

    for i in eachindex(memory)
        if isassigned(memory, i)
            bytes, work = _output_size_budget(memory[i], bytes, work, depth - 1)
            bytes >= 0 || return (-1, 0)
        end
    end
    return (bytes, work)
end

"""
    _within_output_limit(outputs, limit::Int)

Preserve `Base.summarysize(outputs) <= limit`, including shared references and
boundary equality. For common strings and nested dense arrays, first try a
conservative bound without allocating a visited-object set. Duplicate objects
and storage are intentionally charged repeatedly. Unknown values, cycles, deep
or expensive traversals, and bounds above the limit use the original check;
an overestimate is never used to reject an output. `typemax(Int)` disables checks.
"""
@inline function _within_output_limit(outputs, limit::Int)
    limit == typemax(Int) && return true
    if _FAST_OUTPUT_BOUND && limit >= 0
        remaining, _ = _output_size_budget(outputs, limit, _OUTPUT_BOUND_WORK, _OUTPUT_BOUND_DEPTH)
        remaining >= 0 && return true
    end
    return Base.summarysize(outputs) <= limit
end
