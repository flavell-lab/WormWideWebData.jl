"""
    neuron_behavior_correlation(trace_array, behavior, threshold=0.5)

Count neurons whose Pearson correlation with `behavior` is greater than
`threshold`.
"""
function neuron_behavior_correlation(
    trace_array::AbstractMatrix,
    behavior::AbstractVector,
    threshold::AbstractFloat = 0.5,
)

    n_neuron, n_t = size(trace_array)
    n_cor = 0
    for idx_neuron = 1:n_neuron
        if cor(behavior, trace_array[idx_neuron, :]) > threshold
            n_cor += 1
        end
    end

    return n_cor
end

"""
    check_h5_data_integrity(path_h5; check_velocity_cor=false, check_velocity_cor_threshold=0.3, check_velocity_cor_count=10)

Validate expected structure and normalization properties of a dataset HDF5 file,
including the fields required by the paper JSON generator. Optional
velocity-correlation checks can enforce a minimum number of correlated neurons.
"""
function check_h5_data_integrity(
    path_h5::AbstractString;
    check_velocity_cor::Bool = false,
    check_velocity_cor_threshold::AbstractFloat = 0.3,
    check_velocity_cor_count::Integer = 10,
)
    fname = basename(path_h5)
    error_msg(m) = "$fname: $m"

    timing = h5read(path_h5, "timing")
    gcamp = h5read(path_h5, "gcamp")
    behavior = h5read(path_h5, "behavior")

    #### checking data ####

    ## traces ##
    @assert haskey(gcamp, "trace_array") error_msg("missing gcamp trace_array")
    @assert ndims(gcamp["trace_array"]) == 2 error_msg("gcamp trace_array must be a matrix")
    n_neuron, n_t = size(gcamp["trace_array"])
    keys_trace = filter(x->startswith(x, "trace"), keys(gcamp))

    # check trace array dimensions
    for k in keys_trace
        (n_neuron_, n_t_) = size(gcamp[k])
        @assert ((n_neuron, n_t) == (n_neuron_, n_t_)) error_msg(
            "size($k) = ($n_neuron_,$n_t_) does not match ($n_neuron,$n_t)",
        )
    end

    if "trace_array" in keys_trace
        @assert all(isapprox.(mean(gcamp["trace_array"], dims = 2), 0.0, atol = 1e-6)) error_msg(
            "all neurons should have mean=0",
        )
        @assert all(isapprox.(std(gcamp["trace_array"], dims = 2), 1.0, rtol = 1e-6)) error_msg(
            "all neurons should have std=1",
        )
    end

    ## timing ##
    @assert haskey(timing, "timestamp_confocal") error_msg(
        "missing timing timestamp_confocal",
    )
    @assert length(timing["timestamp_confocal"]) == n_t error_msg(
        "length(timing/timestamp_confocal)=$(length(timing["timestamp_confocal"])) does not match n_t=$n_t",
    )
    @assert length(timing["timestamp_confocal"]) >= 2 error_msg(
        "timing/timestamp_confocal must have at least 2 samples",
    )

    ## behavior ##
    for k in ["angular_velocity", "velocity", "head_angle"] # some datasets do not have pumping
        @assert haskey(behavior, k) error_msg("missing behavior $k")
        @assert length(behavior[k]) == n_t error_msg(
            "length(behavior/$k)=$(length(behavior[k])) does not match n_t=$n_t",
        )
    end
    @assert haskey(behavior, "reversal_events") error_msg("missing behavior reversal_events")
    @assert ndims(behavior["reversal_events"]) in (1, 2) error_msg(
        "behavior/reversal_events must be a vector or matrix",
    )

    if check_velocity_cor
        threshold = check_velocity_cor_threshold
        min_v_neuron = check_velocity_cor_count
        n_cor_v = neuron_behavior_correlation(
            gcamp["trace_array"],
            behavior["velocity"],
            threshold,
        )
        @assert n_cor_v >= min_v_neuron error_msg(
            "expected but did not get at least $min_v_neuron neurons with cor to velocity above $threshold. count=$n_cor_v",
        )
    end

    nothing
end

function _h5_dataset_filenames(path_dir::AbstractString)
    @assert isdir(path_dir) "not a directory: $path_dir"

    files = filter(readdir(path_dir)) do filename
        path = joinpath(path_dir, filename)
        isfile(path) && endswith(lowercase(filename), ".h5")
    end
    sort!(files)

    return files
end

"""
    check_h5_datasets_for_paper_json(path_dir; verbose=false)

Validate every direct `.h5` file in `path_dir` for the paper JSON generator.
This reuses `check_h5_data_integrity`, which includes the fields required by
`get_dataset_dict`.
"""
function check_h5_datasets_for_paper_json(
    path_dir::AbstractString;
    verbose::Bool = false,
)
    files = _h5_dataset_filenames(path_dir)
    @assert !isempty(files) "no .h5 files found in $path_dir"

    for filename in files
        verbose && @info "Checking dataset $filename"
        check_h5_data_integrity(joinpath(path_dir, filename))
    end

    nothing
end

"""
    check_paper_h5_datasets(datasets, path_dir_datasets; verbose=false)

For each dataset entry, verify file existence, checksum integrity, and HDF5
content validity via `check_h5_data_integrity`.
"""
function check_paper_h5_datasets(
    datasets::Vector{<:Dict},
    path_dir_datasets::AbstractString;
    verbose::Bool = false,
)
    for dataset in datasets
        verbose && @info "Checking dataset $(dataset["uid"])"
        path_h5 = joinpath(path_dir_datasets, dataset["filename"])
        # check if file exists
        uid = dataset["uid"]
        @assert isfile(path_h5) "$(uid) does not exist at $path_h5"

        # verify checksum
        checksum_compute = sha256(path_h5)
        checksum_stored = dataset["checksum"]

        @assert checksum_compute == checksum_stored "sha256 does not match for $uid.\nexpected: $checksum_stored\ncomputed: $checksum_compute"

        # check behavior and neural data
        check_h5_data_integrity(path_h5)
    end

    nothing
end

function get_file_checksums(
    path_dir::AbstractString;
    ext::Union{Nothing,AbstractString} = nothing,
    f_checksum::Function = WormWideWebData.sha256,
)
    target_ext = isnothing(ext) ? nothing : lowercase(ext)

    files = filter(readdir(path_dir; join = true)) do path
        isfile(path) && (isnothing(target_ext) || endswith(lowercase(path), target_ext))
    end
    sort!(files)

    data = []
    for file in files
        hash = f_checksum(file)

        push!(data, (filename = basename(file), checksum = hash))
    end

    return data
end

function write_file_checksums_to_csv(
    path_dir::AbstractString,
    path_csv::AbstractString;
    ext::Union{Nothing,AbstractString} = nothing,
    f_checksum::Function = WormWideWebData.sha256,
    header::Bool = false,
)
    hashes = get_file_checksums(path_dir, ext = ext, f_checksum = f_checksum)

    open(path_csv, "w") do io
        if header

            write(io, "filename,$(string(f_checksum))\n")
        end

        for row in hashes
            filename = String(row.filename)
            checksum = String(row.checksum)
            write(io, filename, ",", checksum, "\n")
        end
    end

    return path_csv
end
