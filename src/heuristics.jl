"""
    function levenshtein(a::AbstractString, b::AbstractString)

Heuristic cost function for the SyGuS string benchmark, which is the levenshtein distance.
"""
function levenshtein(a::AbstractString, b::AbstractString)
    m, n = length(a), length(b)

    if m < n
        a, b = b, a
        m, n = n, m
    end

    prev = collect(0:n)
    curr = similar(prev)

    for i in 1:m
        curr[1] = i
        for j in 1:n
            cost = a[i] == b[j] ? 0 : 1
            curr[j+1] = min(
                prev[j+1] + 1,
                curr[j] + 1,
                prev[j] + cost
            )
        end
        prev, curr = curr, prev
    end

    return prev[n+1]
end


"""
    hamming_distance(a::UInt64, b::UInt64)

Heuristic cost function for the SyGuS bitvector benchmark, which is the hamming distance.
"""
hamming_distance(a::UInt64, b::UInt64) = count_ones(a ⊻ b)


"""
    hamming_distance(a::Matrix{Int64}, b::Matrix{Int64})

Heuristic cost function for the ARC-AGI-1 benchmark, which is the hamming distance.
"""
function hamming_distance(a::Matrix{Int64}, b::Matrix{Int64}) 
    m1, n1 = size(a)
    m2, n2 = size(b)

    m = min(m1, m2)
    n = min(n1, n2)

    dist = 0

    # overlap region
    for i in 1:m, j in 1:n
        dist += a[i, j] != b[i, j]
    end

    # missing region equals size of both minus twice the overlapping region
    dist += length(a) + length(b) - 2 * m * n

    return dist
end