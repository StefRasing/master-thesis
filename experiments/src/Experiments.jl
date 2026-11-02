"""Shared experiment orchestration. Load after activating the thesis project."""
module Experiments
using HerbCore, HerbSearch, HerbSpecification, HerbBenchmarks, HerbGrammar, HerbInterpret
using RuntimeGeneratedFunctions, DataStructures, JSON3
include("../../src/PhalconModule.jl")
using .Phalcon
include("io.jl")
include("arc_property_grammar.jl")

export ExperimentConfig, benchmark_adapter, run_experiment, main

include("config.jl")
include("benchmarks.jl")
include("runner.jl")
include("cli.jl")

end
