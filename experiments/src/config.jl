Base.@kwdef struct ExperimentConfig
    algorithm::Symbol = :phalcon
    benchmark::Symbol = :strings
    run::String = "1"
    shard::Union{Nothing,String} = nothing
    repetitions::Int = 1
    seed::Int = 1
    timeout::Real = 1800
    reuse_interpreter::Bool = true
    output::Union{Nothing,String} = nothing
    store::Bool = true
    task_names::Union{Nothing,Vector{String}} = nothing
    problem_indices = Colon()
    test_indices::Vector{Int} = [1]
    iterator_options::NamedTuple = (;)
    phalcon_options::NamedTuple = (;)
end

