using JSON

function all_success_times(files)
    vcat([
        [
            r["elapsed_time"]
            for r in JSON.parsefile(f)["results"]
            if r["success"] == true
        ]
        for f in files
    ]...)
end

fs = ["run_1.json", "run_2.json", "run_3.json", "run_4.json", "run_5.json"]
files = ["processing/crossbeam/$f" for f in fs]

times = all_success_times(files)

println("Overall avg success time: ", sum(times) / length(times))