function generate_encoding_files(
    path_dir_target::String,
    path_analysis_dict::String,
    path_fit_results::String,
    path_relative_encoding_strength::String;
    verbose = true,
)
    verbose && @info "computing checksum"
    blake3_analysis_dict = blake3(path_analysis_dict)
    blake3_fit_results = blake3(path_fit_results)
    blake3_relative_encoding_strength = blake3(path_relative_encoding_strength)

    verbose && @info "loading jld2 files"
    analysis_dict = load(path_analysis_dict, "analysis_dict");
    fit_results = load(path_fit_results, "fit_results");
    relative_encoding_strength =
        load(path_relative_encoding_strength, "relative_encoding_strength");

    mkpath(path_dir_target)

    verbose && @info "generating encoding files"

    verbose && @info "saving neuron categorization"
    save_dict_to_h5_json(
        path_dir_target,
        "neuron_categorization",
        analysis_dict["neuron_categorization"],
        metadata = Dict("blake3_analysis_dict"=>blake3_analysis_dict),
    )

    verbose && @info "saving encoding changes corrected"
    save_dict_to_h5_json(
        path_dir_target,
        "encoding_changes_corrected",
        analysis_dict["encoding_changes_corrected"],
        metadata = Dict("blake3_analysis_dict"=>blake3_analysis_dict),
    )

    verbose && @info "saving tuning strength"
    save_dict_to_h5_json(
        path_dir_target,
        "tuning_strength",
        analysis_dict["tuning_strength"],
        metadata = Dict("blake3_analysis_dict"=>blake3_analysis_dict),
    )

    verbose && @info "saving relative encoding strength"
    # save_dict_to_h5(joinpath(path_dir_target, "relative_encoding_strength.h5"), relative_encoding_strength,
    #     metadata=Dict("blake3_relative_encoding_strength"=>blake3_relative_encoding_strength))

    # relative encoding strengths median
    relative_encoding_strength_median = Dict{String,Dict{String,Matrix{Float64}}}()
    for (uid, uid_enc_strength) in relative_encoding_strength
        # 1. identify dimensions and keys safely
        range_keys = keys(uid_enc_strength)
        n_range = length(range_keys)

        # pre_allocate
        first_rg = first(values(uid_enc_strength))
        first_neuron = first(values(first_rg))
        feature_keys = keys(first_neuron)

        n_neuron = maximum(keys(first_rg))

        dict_dataset = Dict{String,Matrix{Float64}}(
            k => zeros(Float64, n_neuron, n_range) for k in feature_keys
        )

        # compute median
        for (i_rg, rg_enc_strength) in uid_enc_strength
            for (idx_neuron, neuron_features) in rg_enc_strength
                for (k, enc_vec) in neuron_features
                    dict_dataset[k][idx_neuron, i_rg] = median(enc_vec)
                end
            end
        end

        relative_encoding_strength_median[uid] = dict_dataset
    end
    save_dict_to_h5_json(
        path_dir_target,
        "relative_encoding_strength_median",
        relative_encoding_strength_median,
        metadata = Dict(
            "blake3_relative_encoding_strength"=>blake3_relative_encoding_strength,
        ),
    )

    verbose && @info "saving tau"
    # decay constants tau (median)
    dict_sampled_tau_vals_median = Dict()
    for (uid, result) in fit_results
        dict_sampled_tau_vals_median[uid] =
            dropdims(median(result["sampled_tau_vals"], dims = 3), dims = 3)
    end
    save_dict_to_h5_json(
        path_dir_target,
        "sampled_tau_vals_median",
        dict_sampled_tau_vals_median,
        metadata = Dict("blake3_fit_results"=>blake3_fit_results),
    )


    verbose && @info "saving fit ranges"
    # model fit ranges
    dict_fit_ranges = Dict()
    for (uid, v) in fit_results
        rgs = v["ranges"]
        rg_array = zeros(Int, length(rgs), 2)

        for (i, rg) in enumerate(rgs)
            rg_array[i, :] .= rg[1], rg[end]
        end

        dict_fit_ranges[uid] = rg_array
    end
    save_dict_to_h5_json(
        path_dir_target,
        "fit_ranges",
        dict_fit_ranges,
        metadata = Dict("blake3_fit_results"=>blake3_fit_results),
    )

    verbose && @info "successfully generated encoding files"

    nothing
end

function _get_median_tuning_strength(
    ranges_encoding::Vector{Int},
    idx_neuron::Int,
    key::AbstractString,
    tuning_strength::Dict,
)
    ranges_encoding_str = string.(ranges_encoding)
    idx_neuron_str = string(idx_neuron)

    median(
        strength[idx_neuron_str][key] for
        (i_rg_str, strength) in tuning_strength if i_rg_str in ranges_encoding_str
    )
end

function get_encoding_dictionary(
    neuron_categorization,
    encoding_changes_corrected,
    tuning_strength,
    sampled_tau_vals_median,
    fit_ranges,
    relative_encoding_strength_median,
)
    n_neuron = size(sampled_tau_vals_median, 2)

    output_ = Dict()

    output_["ranges"] = fit_ranges
    output_["neuron_categorization"] = neuron_categorization
    output_["tau_vals"] = zeros(n_neuron) # time constants

    output_["forwardness"] = zeros(n_neuron)
    output_["dorsalness"] = zeros(n_neuron)
    output_["feedingness"] = zeros(n_neuron)

    output_["rel_enc_str_v"] = zeros(n_neuron) # relative encoding strength
    output_["rel_enc_str_θh"] = zeros(n_neuron)
    output_["rel_enc_str_P"] = zeros(n_neuron)

    rel_enc_str_v = relative_encoding_strength_median["v"]
    rel_enc_str_θh = relative_encoding_strength_median["θh"]
    rel_enc_str_P = relative_encoding_strength_median["P"]

    for idx_neuron = 1:n_neuron
        idx_neuron_str = string(idx_neuron)

        ranges_encoding = Int[]
        ranges_encoding_v = Int[]
        ranges_encoding_θh = Int[]
        ranges_encoding_P = Int[]

        # encoding categorization
        for (i_rg, enc_rg) in neuron_categorization
            i_rg = i_rg isa String ? parse(Int, i_rg) : i_rg

            if idx_neuron in enc_rg["all"]
                push!(ranges_encoding, i_rg)
            end

            enc_v = enc_rg["v"]
            enc_θh = enc_rg["θh"]
            enc_P = enc_rg["P"]

            if idx_neuron in enc_v["fwd"] || idx_neuron in enc_v["rev"]
                push!(ranges_encoding_v, i_rg)
            end
            if idx_neuron in enc_θh["dorsal"] || idx_neuron in enc_θh["ventral"]
                push!(ranges_encoding_θh, i_rg)
            end
            if idx_neuron in enc_P["act"] || idx_neuron in enc_P["inh"]
                push!(ranges_encoding_P, i_rg)
            end
        end

        # compute encoding strengths and forwardness/dorsalness/feedingness only using the encoding time segments/ranges
        if !isempty(ranges_encoding)
            output_["tau_vals"][idx_neuron] =
                median(sampled_tau_vals_median[ranges_encoding, idx_neuron])
            output_["rel_enc_str_v"][idx_neuron] =
                median(rel_enc_str_v[idx_neuron, ranges_encoding])
            output_["rel_enc_str_θh"][idx_neuron] =
                median(rel_enc_str_θh[idx_neuron, ranges_encoding])
            output_["rel_enc_str_P"][idx_neuron] =
                median(rel_enc_str_P[idx_neuron, ranges_encoding])
        end

        if !isempty(ranges_encoding_v)
            output_["forwardness"][idx_neuron] = _get_median_tuning_strength(
                ranges_encoding_v,
                idx_neuron,
                "v_fwd",
                tuning_strength,
            )
        end
        if !isempty(ranges_encoding_θh)
            output_["dorsalness"][idx_neuron] = _get_median_tuning_strength(
                ranges_encoding_θh,
                idx_neuron,
                "θh_dorsal",
                tuning_strength,
            )
        end
        if !isempty(ranges_encoding_P)
            output_["feedingness"][idx_neuron] = _get_median_tuning_strength(
                ranges_encoding_P,
                idx_neuron,
                "P_pos",
                tuning_strength,
            )
        end
    end

    # if more than 1 segments, collate encoding changing neurons
    output_["encoding_changing_neurons"] =
        size(output_["ranges"], 1) > 1 ?
        unique(vcat([enc["all"] for (rg, enc) in encoding_changes_corrected]...)) : []

    output_
end
