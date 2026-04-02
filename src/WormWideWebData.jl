module WormWideWebData

using HDF5
using JSON
using JLD2
using Statistics
using Scratch
using CSV
using HTTP
using Downloads
using ProgressMeter

include("io.jl")
include("label.jl")
include("encoding.jl")
include("data_integrity.jl")
include("reference.jl")
include("api/zenodo.jl")
include("data_generator.jl")

# encoding.jl
export generate_encoding_files, get_encoding_dictionary
# label.jl
export generate_neuropal_json
# data_integrity.jl
export check_h5_data_integrity
# reference.jl
export get_activity_info
# io.jl
export load_dict_from_h5, load_dict_from_json
# data_generator.jl
export generate_paper_datasets_json

end # module WormWideWebData
