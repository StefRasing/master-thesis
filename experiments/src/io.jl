function validate_config_value(x)
    x isa Function && throw(ArgumentError("function-valued configuration overrides cannot be archived; define behavior in versioned adapter code"))
    if x isa Union{NamedTuple,AbstractDict}
        foreach(validate_config_value, values(x))
    elseif x isa Union{Tuple,AbstractArray}
        foreach(validate_config_value, x)
    end
    return nothing
end

# Canonical JSON makes identities independent of dictionary insertion order.
function json_value(x)
    x isa Union{Nothing,Bool,Number,AbstractString} && return x
    x isa Symbol && return string(x)
    x isa Colon && return ":"
    x isa Function && return Dict("function" => string(x))
    x isa Module && return string(x)
    x isa NamedTuple && return Dict(string(k) => json_value(v) for (k,v) in pairs(x))
    x isa AbstractDict && return Dict(string(k) => json_value(v) for (k,v) in pairs(x))
    x isa Union{Tuple,AbstractArray,AbstractRange} && return [json_value(v) for v in x]
    throw(ArgumentError("unsupported configuration value $(typeof(x)); use JSON-compatible values"))
end
function canonical_json(x)
    value = json_value(x)
    value isa AbstractDict && return "{" * join([JSON3.write(k) * ":" * canonical_json(value[k]) for k in sort!(collect(keys(value)))], ",") * "}"
    value isa AbstractVector && return "[" * join(canonical_json.(value), ",") * "]"
    return JSON3.write(value)
end
fingerprint(x) = bytes2hex(sha256(canonical_json(x)))

function source_snapshot(root)
    files = Dict{String,String}()
    for subdir in ("src", "experiments/src")
        dir = joinpath(root, subdir)
        isdir(dir) || continue
        for (base, _, names) in walkdir(dir), name in names
            endswith(name, ".jl") || continue
            path = joinpath(base, name)
            files[relpath(path, root)] = bytes2hex(sha256(read(path)))
        end
    end
    git(args...) = try
        strip(read(pipeline(`git -C $root $args`; stderr=devnull), String))
    catch
        nothing
    end
    return Dict("revision" => git("rev-parse", "HEAD"),
        "dirty" => git("diff", "HEAD", "--", "src", "experiments/src", "Project.toml", "Manifest.toml"), "source_sha256" => fingerprint(files), "source_files_sha256" => files)
end

function run_provenance()
    root = normpath(joinpath(@__DIR__, "../.."))
    project = Base.active_project()
    isnothing(project) && error("Activate the thesis project before running experiments")
    manifest = joinpath(dirname(project), "Manifest.toml")
    normpath(project) == joinpath(root, "Project.toml") || error("Activate the thesis project before running experiments")
    isfile(manifest) || error("Instantiate the environment before running experiments (Manifest.toml missing)")
    # Capture the actually loaded interpreter too (tests may use a sibling checkout).
    interpreter_root = dirname(dirname(pathof(HerbInterpret)))
    return Dict("code" => source_snapshot(root), "environment" => Dict(
        "julia_version" => string(VERSION), "machine" => Sys.MACHINE,
        "threads" => Threads.nthreads(), "project_toml" => read(project, String),
        "manifest_toml" => read(manifest, String),
        "local_preferences" => isfile(joinpath(dirname(project), "LocalPreferences.toml")) ? read(joinpath(dirname(project), "LocalPreferences.toml"), String) : nothing,
        "interpreter" => source_snapshot(interpreter_root)))
end

"""Readable filename with the full identity hash to distinguish configurations."""
function result_filename(identity)
    slug = replace(string(identity["problem"]), r"[^A-Za-z0-9._-]+" => "_")
    slug = first(slug, 80)
    isempty(slug) && (slug = "problem")
    return "$(slug)__rep-$(identity["repetition"])__seed-$(identity["seed"])__$(fingerprint(identity)).json"
end

"""Publish complete JSON without replacing an existing concurrent winner."""
function publish_json(destination, value)
    mkpath(dirname(destination))
    temporary, io = mktemp(dirname(destination))
    try
        JSON3.pretty(io, value)
        flush(io)
        close(io)
        try
            hardlink(temporary, destination)
        catch
            isfile(destination) || rethrow()
            # Verify the winner is a complete, parseable record.
            JSON3.read(read(destination, String))
        end
    finally
        isopen(io) && close(io)
        rm(temporary; force=true)
    end
    return destination
end

"""Store shared provenance once; result records contain only its hash."""
function save_provenance(path, provenance)
    hash = fingerprint(provenance)
    destination = publish_json(joinpath(path, "provenance", hash * ".json"), provenance)
    fingerprint(JSON3.read(read(destination, String))) == hash || error("provenance hash mismatch")
    return hash
end

function append_result(path, record)
    isfile(path) && throw(ArgumentError("output must be a run directory; legacy JSON arrays are read-only"))
    directory = get(record, "schema_version", 2) >= 3 ? joinpath(path, "results") : path
    destination = joinpath(directory, result_filename(record["identity"]))
    publish_json(destination, record)
    existing = JSON3.read(read(destination, String))
    existing["identity"] == JSON3.read(canonical_json(record["identity"])) || error("run identity collision")
    return destination
end

function completed_run(path, identity)
    candidates = (joinpath(path, "results", result_filename(identity)),
        joinpath(path, result_filename(identity)), joinpath(path, fingerprint(identity) * ".json"))
    index = findfirst(isfile, candidates)
    isnothing(index) && return false
    destination = candidates[index]
    record = JSON3.read(read(destination, String))
    record["schema_version"] in (2, 3) || error("unsupported result schema")
    record["identity"] == JSON3.read(canonical_json(identity)) || error("run identity mismatch")
    if record["schema_version"] == 3
        snapshot = joinpath(path, "provenance", record["provenance_sha256"] * ".json")
        isfile(snapshot) || return false
    end
    return haskey(record, "result")
end

"""Read v2/v3 run directories, or a legacy JSON array for analysis."""
function load_results(path)
    isfile(path) && return JSON3.read(read(path, String), Vector{Any})
    isdir(path) || return Any[]
    records = Any[]
    for directory in (path, joinpath(path, "results"))
        isdir(directory) || continue
        for f in sort(readdir(directory))
            endswith(f, ".json") || continue
            push!(records, JSON3.read(read(joinpath(directory, f), String)))
        end
    end
    return records
end

"""Export the old flat result array for existing processing scripts."""
function export_legacy(path, destination)
    results = [haskey(r, "schema_version") ? r["result"] : r for r in load_results(path)]
    open(destination, "w") do io
        JSON3.pretty(io, results)
    end
    return destination
end

"""Move embedded v2 provenance into shared snapshots without changing run identity."""
function compact_results!(path)
    converted = 0
    for record in load_results(path)
        get(record, "schema_version", nothing) in (2, 3) || continue
        haskey(record, "provenance") || continue
        provenance = record["provenance"]
        hash = save_provenance(path, provenance)
        hash == record["identity"]["provenance_sha256"] || error("provenance hash mismatch")
        compact = Dict{String,Any}(string(k)=>v for (k,v) in pairs(record) if string(k) != "provenance")
        compact["schema_version"] = 3
        compact["provenance_sha256"] = hash
        destination = joinpath(path, "results", result_filename(record["identity"]))
        mkpath(dirname(destination))
        temporary, io = mktemp(dirname(destination))
        try
            JSON3.pretty(io, compact)
            close(io)
            Base.Filesystem.rename(temporary, destination)
        finally
            isopen(io) && close(io)
            isfile(temporary) && rm(temporary)
        end
        # Remove the old copy only after both snapshot and compact result exist.
        for filename in (result_filename(record["identity"]), record["run_id"] * ".json")
            old = joinpath(path, filename)
            isfile(old) && rm(old)
        end
        converted += 1
    end
    return converted
end
