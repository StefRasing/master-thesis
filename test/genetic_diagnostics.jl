@testset "Optional ancestry preserves search and RNG state" begin
    tracked = contract_iterator(; track_ancestry=true)
    untracked = contract_iterator()
    @test tracked.track_ancestry
    @test !untracked.track_ancestry
    calls = [0, 0]
    for (i, iter) in enumerate((tracked, untracked))
        iter.cost = _ -> (calls[i] += 1; 1)
        parent = RuleNodeWithRuleCounts(iter, RuleNode(3, [RuleNode(1), RuleNode(2)]))
        push!(iter.population, Individual(iter, parent))
    end
    for _ in 1:5
        Phalcon.combine!(tracked)
        Phalcon.combine!(untracked)
        @test RuleNode.(getfield.(tracked.population, :program)) == RuleNode.(getfield.(untracked.population, :program))
        @test getfield.(tracked.population, :cost) == getfield.(untracked.population, :cost)
        @test tracked.programs_evaluated == untracked.programs_evaluated
        @test calls[1] == calls[2]
        @test rand(copy(tracked.rng), UInt64) == rand(copy(untracked.rng), UInt64)
        @test all(ind -> ind.parents === nothing && ind.crossover === nothing &&
            ind.crossover_parts === nothing && ind.mutation === nothing, untracked.population)
    end
    # Exercise both diagnostic constructors even when population selection rejects offspring.
    parent = first(tracked.population)
    program = parent.program
    for iter in (tracked, untracked)
        mutated = Individual(iter, program, parent, :replace)
        crossed = Individual(iter, program, (parent, parent), program, (program, program), :none)
        @test (mutated.parents === parent) == iter.track_ancestry
        @test (crossed.parents === nothing) == !iter.track_ancestry
        @test (crossed.crossover === program) == iter.track_ancestry
        # Printing remains usable with and without history.
        mktemp() do _, io
            redirect_stdout(io) do
                Phalcon.pretty_print(mutated, iter.solver.grammar)
                Phalcon.pretty_print(crossed, iter.solver.grammar)
            end
            flush(io)
            @test position(io) > 0
        end
    end
end

@testset "Supplied interpreter preserves seeded search" begin
    fresh = contract_iterator(; candidate_pool_size=30)
    original = contract_iterator().interpreter
    @test fresh.interpreter !== original
    shared = contract_iterator(; candidate_pool_size=30, interpreter=original)
    @test shared.interpreter === original
    for iter in (fresh, shared)
        parent = RuleNodeWithRuleCounts(iter, RuleNode(3, [RuleNode(1), RuleNode(2)]))
        push!(iter.population, Individual(iter, parent))
    end
    for _ in 1:3
        Phalcon.combine!(fresh)
        Phalcon.combine!(shared)
        @test RuleNode.(getfield.(fresh.population, :program)) == RuleNode.(getfield.(shared.population, :program))
        @test getfield.(fresh.population, :cost) == getfield.(shared.population, :cost)
        @test getfield.(getfield.(fresh.population, :program), :outputs) == getfield.(getfield.(shared.population, :program), :outputs)
        @test fresh.programs_evaluated == shared.programs_evaluated
        @test rand(copy(fresh.rng), UInt64) == rand(copy(shared.rng), UInt64)
    end
    independent = contract_iterator(; candidate_pool_size=30)
    @test independent.interpreter !== original
end
