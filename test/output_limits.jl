using Random

@testset "Conservative output bounds preserve the exact limit" begin
    fits = Phalcon._within_output_limit
    bound(x, limit) = first(Phalcon._output_size_budget(x, limit,
        Phalcon._OUTPUT_BOUND_WORK, Phalcon._OUTPUT_BOUND_DEPTH))
    grid = reshape(collect(1:12), 3, 4)
    object = [(1, CartesianIndex(1, 2)), (2, CartesianIndex(2, 3))]
    values = Any[
        Int[], [1,2,3], UInt64[1,2,3], Bool[true,false], fill(nothing,3),
        Union{Nothing,Int}[1,nothing,3], Union{Nothing,String}["one",nothing,"é🙂"],
        CartesianIndex.([(1,2),(3,4)]), object, [object,copy(object)],
        grid, [grid,copy(grid)], [[grid], [copy(grid)]],
        ["", "one", "é🙂"], Any[1,true,"a",nothing,grid,object],
    ]
    for x in values
        size = Base.summarysize(x)
        for limit in unique([-1,0,max(0,size-1),size,size+1,1024^2,typemax(Int)])
            @test fits(x,limit) == (limit==typemax(Int) || size<=limit)
            if limit>=0 && limit!=typemax(Int) && Phalcon._FAST_OUTPUT_BOUND
                remaining = bound(x,limit)
                @test remaining<0 || size<=limit-remaining<=limit
            end
        end
        @test fits(x,1024^2)
    end

    @testset "Backing capacity and references outside visible ranges" begin
        if Phalcon._FAST_OUTPUT_BOUND
            a=Int[1,2,3];sizehint!(a,4096)
            b=copy(a);resize!(b,0)
            storage=Any[zeros(Int,1000),"retained",zeros(Int,2000)]
            # A separate Array descriptor shares the full Memory, exposing only one
            # element. summarysize still follows the invisible assigned references.
            slice=Base.wrap(Array,getfield(storage,:ref),(1,))
            offset=Base.wrap(Array,Core.memoryref(getfield(storage,:ref),2),(1,))
            for x in (a,b,slice,offset,reshape(a,1,3),[a,reshape(a,1,3)],
                      Vector{Union{Nothing,Int}}(undef,100),Vector{String}(undef,8))
                size=Base.summarysize(x)
                @test !fits(x,size-1)
                @test fits(x,size)
                @test fits(x,size+100)
                remaining=bound(x,typemax(Int)-1)
                @test remaining<0 || size<=typemax(Int)-1-remaining
            end
            @test Base.summarysize(slice)>sizeof(slice)+1000
        end
    end

    @testset "Overestimates fall back instead of rejecting shared data" begin
        shared=zeros(Int,1000)
        for x in ([shared,shared], [shared,reshape(shared,10,100)], fill("a"^1000,5))
            size=Base.summarysize(x)
            Phalcon._FAST_OUTPUT_BOUND && @test bound(x,size)<0
            @test fits(x,size)
            @test !fits(x,size-1)
        end
    end

    @testset "Unsupported graphs, cycles, and bounded work" begin
        captured=zeros(Int,100)
        closure=let captured=captured; ()->sum(captured);end
        cycle=Any[];push!(cycle,cycle)
        deep=Any[1]
        for _ in 1:20;deep=Any[deep];end
        broad=[Int[] for _ in 1:Phalcon._OUTPUT_BOUND_WORK+1]
        for x in (Any[closure], [big(2)^1000], [view(captured,1:2)],
                  [SubString("x"^10000,1:2)], BitVector([true,false]),cycle,deep,broad)
            size=Base.summarysize(x)
            @test fits(x,size)
            @test !fits(x,size-1)
            @test fits(x,typemax(Int))
        end
        if Phalcon._FAST_OUTPUT_BOUND
            @test bound(cycle,1024^2)<0
            @test bound(deep,1024^2)<0
            @test bound(broad,1024^2)<0
        end
    end

    @testset "Random supported nested values and aliases" begin
        rng=Random.Xoshiro(717)
        for _ in 1:150
            grids=[rand(rng,Int,rand(rng,0:6),rand(rng,0:6)) for _ in 1:rand(rng,1:6)]
            rand(rng,Bool) && push!(grids,first(grids))
            x=rand(rng,Bool) ? Any[grids,grids] : grids
            size=Base.summarysize(x)
            for limit in (max(0,size-1),size,size+rand(rng,0:100),1024^2)
                @test fits(x,limit)==(size<=limit)
            end
        end
    end
end
