function pretty_print(ind::Individual, grammar::AbstractGrammar)
    println(rulenode2expr(ind.program, grammar))
    _pretty_print(ind, "", grammar)
end


function _pretty_print(ind::Individual, prefix::String, grammar::AbstractGrammar)
    ind.parents === nothing && return

    if ind.parents isa Tuple
        p1, p2 = ind.parents
        replacement, removed = ind.crossover_parts

        # Meta
        println(prefix * "├── Parent 1:        ", rulenode2expr(p1.program, grammar))
        println(prefix * "│   └── replacement: ", rulenode2expr(replacement, grammar))
        println(prefix * "├── Parent 2:        ", rulenode2expr(p2.program, grammar))
        println(prefix * "│   └── removed:     ", rulenode2expr(removed, grammar))

        if ind.mutation != :none
            println(prefix * "├── Crossover:       ", rulenode2expr(ind.crossover, grammar))
            println(prefix * "│   ├── mutation:    ", ind.mutation)
            println(prefix * "│   └── result:      ", rulenode2expr(ind.program, grammar))
        end

        # parent 1
        if !isnothing(p1.parents)
            println(prefix * "├── Parent 1 origin:")
            _pretty_print(p1, prefix * "│   ", grammar)
        else
            println(prefix * "├── Parent 1 origin: extensions")
        end

        # parent 2
        if !isnothing(p2.parents)
            println(prefix * "└── Parent 2 origin: ")
            _pretty_print(p2, prefix * "    ", grammar)
        else
            println(prefix * "└── Parent 2 origin: extensions")
        end
    else
        p = ind.parents

        println(prefix * "├── Parent:       ", rulenode2expr(p.program, grammar))
        println(prefix * "│   ├── mutation: ", ind.mutation)
        println(prefix * "│   └── result:   ", rulenode2expr(ind.program, grammar))

        # parent
        if !isnothing(p.parents)
            println(prefix * "└── Parent origin:")
            _pretty_print(p, prefix * "    ", grammar)
        else
            println(prefix * "└── Parent origin:   extension")
        end
    end
end

