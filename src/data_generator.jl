"""
    compute_mean_timestep(timestamp_confocal, max_segment_gap=1)

Estimate a robust mean timestep by ignoring large timestamp jumps interpreted
as segment boundaries.
"""
function compute_mean_timestep(timestamp_confocal::Vector, max_segment_gap::Int = 1)
    list_diff = diff(timestamp_confocal)
    list_idx = list_diff .< 1.2 * median(list_diff)
    n_jump = length(list_diff) - sum(list_idx)
    @assert n_jump <= max_segment_gap "more than 1 large gap found in timestamp_confocal: n_jump=$n_jump"
    mean(list_diff[list_idx])
end

"""
    parse_event_str(str)

Parse an event string formatted like `"event=[1,2],other=[3]"` into a vector
of `[event_name, index]` pairs.
"""
function parse_event_str(str::AbstractString)
    list_event = Vector{Vector{Any}}()
    for m in eachmatch(r"([^=,\s]+)\s*=\s*\[([^\]]*)\]", str)
        event_name = strip(m.captures[1])
        idx_values = strip(m.captures[2])
        isempty(idx_values) && continue

        for idx_str in split(idx_values, ',')
            idx_clean = strip(idx_str)
            isempty(idx_clean) && continue
            push!(list_event, Any[event_name, parse(Int, idx_clean)])
        end
    end

    return list_event
end

"""
    get_dataset_dict(path_h5_original; θh_pos_is_ventral, h5_checksum, source_filename, paper_id, dataset_type, dict_encoding=nothing, dict_label=nothing, events_str=nothing)

Convert a source HDF5 dataset into the normalized dictionary schema used for
JSON export.
"""
function get_dataset_dict(
    path_h5_original::AbstractString;
    θh_pos_is_ventral::Bool,
    h5_checksum::AbstractString,
    source_filename::AbstractString,
    paper_id::AbstractString,
    dataset_type::Vector{<:AbstractString},
    dict_encoding::Union{Dict,Nothing} = nothing,
    dict_label::Union{Dict,Nothing} = nothing,
    events_str::Union{AbstractString,Nothing,Missing} = nothing,
)
    dv_correction = θh_pos_is_ventral ? -1 : 1

    timing = h5read(path_h5_original, "timing")
    behavior = h5read(path_h5_original, "behavior")
    gcamp = h5read(path_h5_original, "gcamp")

    out_ = Dict()
    out_["metadata"] = Dict(
        "checksum"=>h5_checksum,
        "source_filename"=>source_filename,
        "paper_id"=>paper_id,
    )
    out_["dataset_type"] = dataset_type

    if !isnothing(dict_encoding)
        out_["encoding"] = dict_encoding
    end
    if !isnothing(dict_label)
        out_["label"] = dict_label
    end

    # timing
    out_["timing"] = Dict(
        "mean_timestep"=>compute_mean_timestep(timing["timestamp_confocal"]),
        "timestamp_confocal"=>timing["timestamp_confocal"],
        "max_t"=>size(gcamp["trace_array"], 2), # [n_neuron, n_t]
    )
    if !isnothing(events_str) && !ismissing(events_str)
        out_["timing"]["event"] = parse_event_str(events_str)
    end

    # behavior
    out_["behavior"] = Dict(
        b=>behavior[b] for
        b in ["angular_velocity", "head_angle", "velocity", "reversal_events"]
    )
    out_["behavior"]["head_angle"] .*= dv_correction
    out_["behavior"]["angular_velocity"] .*= dv_correction

    # gcamp
    out_["gcamp"] = Dict("trace_array"=>gcamp["trace_array"]) # must
    for k in ["trace_array_original"]
        if haskey(gcamp, k)
            out_["gcamp"][k] = gcamp[k]
        end
    end

    out_
end

"""
    generate_paper_datasets_json(path_dir_output, path_dir_paper, paper_id, datasets; neuropal_label=false, encoding_data=false, dir_datasets="datasets")

Generate one JSON file per dataset entry for a paper after validating source
HDF5 files and optionally attaching encoding/label metadata.
"""
function generate_paper_datasets_json(
    path_dir_output::AbstractString,
    path_dir_paper::AbstractString,
    paper_id::AbstractString,
    datasets::Vector{<:Dict};
    neuropal_label::Bool = false,
    encoding_data::Bool = false,
    dir_datasets::AbstractString = "datasets",
)

    # load encoding and neuropal data
    neuron_categorization = nothing
    encoding_changes_corrected = nothing
    relative_encoding_strength_median = nothing
    tuning_strength = nothing
    sampled_tau_vals_median = nothing
    fit_ranges = nothing
    neuropal_data = nothing

    if encoding_data
        @info "loading encoding data files"
        neuron_categorization =
            load_dict_from_h5(joinpath(path_dir_paper, "neuron_categorization.h5"))
        encoding_changes_corrected =
            load_dict_from_h5(joinpath(path_dir_paper, "encoding_changes_corrected.h5"))
        relative_encoding_strength_median = load_dict_from_h5(
            joinpath(path_dir_paper, "relative_encoding_strength_median.h5"),
        )
        tuning_strength = load_dict_from_h5(joinpath(path_dir_paper, "tuning_strength.h5"))
        sampled_tau_vals_median =
            load_dict_from_h5(joinpath(path_dir_paper, "sampled_tau_vals_median.h5"))
        fit_ranges = load_dict_from_h5(joinpath(path_dir_paper, "fit_ranges.h5"))
    end
    if neuropal_label
        @info "loading neuropal data"
        neuropal_data = load_dict_from_json(joinpath(path_dir_paper, "neuropal_label.json"))
    end

    path_dir_dataset = joinpath(path_dir_paper, dir_datasets)
    path_dir_json = joinpath(path_dir_output, paper_id)
    mkpath(path_dir_json)

    # check integrity
    check_paper_h5_datasets(datasets, path_dir_dataset)

    @info "generating json files..."
    @showprogress for dataset in datasets
        uid = dataset["uid"]
        fname = dataset["filename"]

        path_h5 = joinpath(path_dir_dataset, fname)

        dict_encoding =
            encoding_data ?
            WormWideWebData.get_encoding_dictionary(
                neuron_categorization[uid],
                encoding_changes_corrected[uid],
                tuning_strength[uid],
                sampled_tau_vals_median[uid],
                fit_ranges[uid],
                relative_encoding_strength_median[uid],
            ) : nothing
        dict_label =
            neuropal_label && haskey(neuropal_data, uid) ?
            neuropal_data[uid]["roi_to_neuron"] : nothing

        # generate output dict
        dict_output = get_dataset_dict(
            path_h5,
            θh_pos_is_ventral = dataset["θh_pos_is_ventral"],
            dataset_type = split(dataset["type"], ","),
            dict_encoding = dict_encoding,
            dict_label = dict_label,
            events_str = dataset["event"],
            h5_checksum = dataset["checksum"],
            source_filename = dataset["filename"],
            paper_id = paper_id,
        )

        # write to json
        path_json = joinpath(path_dir_json, "$(paper_id)_$(uid).json")
        open(path_json, "w") do f
            JSON.print(f, dict_output)
        end
    end
end

"""
    generate_all_paper_json(path_dir_root_output, path_dir_root_source)

Fetch activity metadata and generate dataset JSON outputs for all supported
papers in the reference catalog.
"""
function generate_all_paper_json(
    path_dir_root_output::AbstractString,
    path_dir_root_source::AbstractString,
)
    papers_data, datasets_data, dataset_types = get_activity_info()
    papers_data = Dict(paper["paper_id"] => paper for paper in papers_data)

    for paper_id in keys(papers_data)
        @info "processing paper $paper_id"
        path_dir_paper = joinpath(path_dir_root_source, paper_id)
        q_neuropal_label = papers_data[paper_id]["neuropal_label"]
        q_encoding_data = papers_data[paper_id]["encoding_data"]

        if !haskey(papers_data[paper_id], "repository")
            continue
        end
        type_repo = papers_data[paper_id]["repository"]["type"]
        if type_repo == "zenodo"
            zenodo_id = papers_data[paper_id]["repository"]["record_id"]

            prepare_files_zenodo(
                zenodo_id,
                path_dir_paper,
                neuropal_label = q_neuropal_label,
                encoding_data = q_encoding_data,
            )

            generate_paper_datasets_json(
                path_dir_root_output,
                path_dir_paper,
                paper_id,
                datasets_data[paper_id],
                neuropal_label = q_neuropal_label,
                encoding_data = q_encoding_data,
            )
        elseif type_repo == "dryad"
        end
    end
end
