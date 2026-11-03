Base.@kwdef struct ExperimentConfig
    algorithm::Symbol = :phalcon
    benchmark::Symbol = :strings
    run::String = "1"
    shard::Union{Nothing,String} = nothing
    repetitions::Int = 1
    seed::Int = 1
    timeout::Real = 1800
    verbose::Bool = false
    reuse_interpreter::Bool = true
    timing_protocol::Symbol = :warmed_v1
    output::Union{Nothing,String} = nothing
    store::Bool = true
    task_names::Union{Nothing,Vector{String}} = nothing
    problem_indices = Colon()
    test_indices::Union{Nothing,Vector{Int}} = nothing
    iterator_options::NamedTuple = (;)
    phalcon_options::NamedTuple = (;)
end

