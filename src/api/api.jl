function generate_download_manifest(
    path_dir_target::AbstractString;
    encoding_data::Bool = false,
    neuropal_label::Bool = false,
)
    manifest = [("processed_h5.tar.bz2", joinpath(path_dir_target, "datasets")),]

    if encoding_data
        manifest = vcat(
            manifest,
            [
                ("neuron_categorization.h5.bz2", nothing),
                ("encoding_changes_corrected.h5.bz2", nothing),
                ("relative_encoding_strength_median.h5.bz2", nothing),
                ("tuning_strength.h5.bz2", nothing),
                ("sampled_tau_vals_median.h5.bz2", nothing),
                ("fit_ranges.h5.bz2", nothing),
            ],
        )
    end
    neuropal_label && push!(manifest, ("neuropal_label.json.bz2", nothing))

    return manifest
end

include("dryad.jl")
include("zenodo.jl")
