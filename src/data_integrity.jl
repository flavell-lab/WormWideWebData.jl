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

function check_h5_data_integrity(
    path_h5::AbstractString;
    check_velocity_cor::Bool = false,
    check_velocity_cor_threshold::AbstractFloat = 0.3,
    check_velocity_cor_count::Integer = 10,
)
    fname = basename(path_h5)
    error_msg(m) = "$fname: $m"

    gcamp = h5read(path_h5, "gcamp")
    behavior = h5read(path_h5, "behavior")

    #### checking data ####

    ## traces ##
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

    ## behavior ##
    for k in ["velocity", "head_angle"] # some datasets do not have pumping
        @assert haskey(behavior, k) error_msg("missing behavior $k")
    end

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

function check_paper_h5_datasets(
    datasets::Dict,
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
