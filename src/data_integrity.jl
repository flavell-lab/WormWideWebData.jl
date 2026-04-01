function check_h5_data_integrity(path_h5::AbstractString, check_velocity_cor::Bool = false)
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
        threshold = 0.3
        min_v_neuron = 10
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
