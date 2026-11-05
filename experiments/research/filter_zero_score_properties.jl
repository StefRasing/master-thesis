"""Postprocess a completed property ranking without changing the source file."""
module ZeroScorePropertyFilter
using JSON3, SHA, Dates

function remove_zero_scores(report::AbstractDict)
    rows = report["ranking"]
    all(r -> r["score"] isa Real && r["score"] >= 0, rows) ||
        throw(ArgumentError("expected nonnegative property scores"))
    result = Dict{String,Any}(report)
    result["ranking"] = filter(r -> r["score"] > 0, rows)
    result["zero_total_score_properties_removed"] = count(r -> r["score"] == 0, rows)
    return result
end

function main(args=ARGS)
    length(args) == 2 || throw(ArgumentError("usage: filter_zero_score_properties.jl INPUT.json OUTPUT.json"))
    input, output = abspath.(args)
    input != output || throw(ArgumentError("input and output must differ"))
    ispath(output) && throw(ArgumentError("output already exists; choose a new path to preserve results"))
    raw = read(input, String)
    report = JSON3.read(raw, Dict{String,Any})
    get(report, "complete", false) || throw(ArgumentError("input ranking is incomplete"))
    result = remove_zero_scores(report)
    result["postprocessing"] = Dict("operation" => "retain properties with total score > 0; per-task zeros remain allowed",
        "input" => input, "input_sha256" => bytes2hex(sha256(raw)),
        "script_sha256" => bytes2hex(sha256(read(@__FILE__))), "created_at" => string(now()))
    mkpath(dirname(output))
    open(output, "w") do io
        JSON3.pretty(io, result)
        println(io)
    end
    println("Removed $(result["zero_total_score_properties_removed"]) zero-total properties; retained $(length(result["ranking"])) in $output")
    return result
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    ZeroScorePropertyFilter.main()
end
