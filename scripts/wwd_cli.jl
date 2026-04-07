#!/usr/bin/env julia

using JSON
using WormWideWebData

function _usage(io::IO = stdout)
    println(
        io,
        """
Usage:
  wwd_cli.jl all-json <output_dir> <source_dir>
  wwd_cli.jl encoding-files <target_dir> <analysis_dict.jld2> <fit_results.jld2> <relative_encoding_strength.jld2>
  wwd_cli.jl neuropal-json <target_dir> <neuropal_dict.jld2> [--json-name NAME] [--key-dataset KEY] [--key-sub KEY] [--overwrite]
  wwd_cli.jl paper-json <output_dir> <paper_dir> <paper_id> <datasets.json> [--neuropal-label] [--encoding-data] [--dir-datasets NAME]

Examples:
  wwd_cli.jl all-json /output /workspace
  wwd_cli.jl encoding-files /workspace/kfc_encoding_h5 /workspace/analysis_dict.jld2 /workspace/fit_results.jld2 /workspace/relative_encoding_strength.jld2
  wwd_cli.jl neuropal-json /workspace /workspace/dict_neuropal_label.jld2 --overwrite
  wwd_cli.jl paper-json /output /workspace/atanas_kim_2023 atanas_kim_2023 /workspace/datasets.json --encoding-data --neuropal-label
""",
    )
end

function _fail(msg::AbstractString)
    println(stderr, "Error: $msg")
    _usage(stderr)
    return 1
end

function _take_value!(args::Vector{String}, flag::AbstractString)
    isempty(args) && error("missing value for $flag")
    return popfirst!(args)
end

function _load_datasets(path_json::AbstractString)
    data = JSON.parsefile(path_json, dicttype = Dict)

    if data isa Vector
        rows = data
    elseif data isa Dict && haskey(data, "datasets") && data["datasets"] isa Vector
        rows = data["datasets"]
    else
        error("datasets JSON must be an array or an object with key \"datasets\"")
    end

    out = Dict{String,Any}[]
    for (i, row) in enumerate(rows)
        row isa Dict || error("datasets[$i] is not an object")
        push!(out, Dict{String,Any}(string(k) => v for (k, v) in row))
    end

    return out
end

function main(args::Vector{String} = copy(ARGS))
    if isempty(args)
        _usage(stderr)
        return 1
    end

    cmd = popfirst!(args)
    if cmd in ("help", "-h", "--help")
        _usage()
        return 0
    end

    try
        if cmd == "all-json"
            length(args) == 2 || return _fail("all-json requires <output_dir> <source_dir>")
            output_dir = args[1]
            source_dir = args[2]
            WormWideWebData.generate_all_paper_json(output_dir, source_dir)
            return 0
        end

        if cmd == "encoding-files"
            length(args) == 4 || return _fail(
                "encoding-files requires <target_dir> <analysis_dict.jld2> <fit_results.jld2> <relative_encoding_strength.jld2>",
            )
            WormWideWebData.generate_encoding_files(args[1], args[2], args[3], args[4])
            return 0
        end

        if cmd == "neuropal-json"
            length(args) >= 2 ||
                return _fail("neuropal-json requires <target_dir> <neuropal_dict.jld2>")
            target_dir = popfirst!(args)
            path_neuropal = popfirst!(args)

            json_name = "neuropal_label.json"
            key_dataset = "dict_neuropal_label"
            key_sub = nothing
            overwrite = false

            while !isempty(args)
                arg = popfirst!(args)
                if arg == "--overwrite"
                    overwrite = true
                elseif arg == "--json-name"
                    json_name = _take_value!(args, "--json-name")
                elseif arg == "--key-dataset"
                    key_dataset = _take_value!(args, "--key-dataset")
                elseif arg == "--key-sub"
                    key_sub = _take_value!(args, "--key-sub")
                else
                    return _fail("unknown option for neuropal-json: $arg")
                end
            end

            WormWideWebData.generate_neuropal_json(
                target_dir,
                path_neuropal,
                true;
                json_name = json_name,
                key_dataset = key_dataset,
                key_sub = key_sub,
                overwrite = overwrite,
            )
            return 0
        end

        if cmd == "paper-json"
            length(args) >= 4 || return _fail(
                "paper-json requires <output_dir> <paper_dir> <paper_id> <datasets.json>",
            )
            output_dir = popfirst!(args)
            paper_dir = popfirst!(args)
            paper_id = popfirst!(args)
            path_datasets_json = popfirst!(args)

            neuropal_label = false
            encoding_data = false
            dir_datasets = "datasets"

            while !isempty(args)
                arg = popfirst!(args)
                if arg == "--neuropal-label"
                    neuropal_label = true
                elseif arg == "--encoding-data"
                    encoding_data = true
                elseif arg == "--dir-datasets"
                    dir_datasets = _take_value!(args, "--dir-datasets")
                else
                    return _fail("unknown option for paper-json: $arg")
                end
            end

            datasets = _load_datasets(path_datasets_json)
            WormWideWebData.generate_paper_datasets_json(
                output_dir,
                paper_dir,
                paper_id,
                datasets;
                neuropal_label = neuropal_label,
                encoding_data = encoding_data,
                dir_datasets = dir_datasets,
            )
            return 0
        end

        return _fail("unknown command: $cmd")
    catch e
        showerror(stderr, e)
        println(stderr)
        Base.show_backtrace(stderr, catch_backtrace())
        return 1
    end
end

exit(main())
