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