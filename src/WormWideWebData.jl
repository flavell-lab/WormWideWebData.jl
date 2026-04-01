module WormWideWebData

using HDF5
using JSON
using JLD2
using Statistics

include("io.jl")
include("label.jl")
include("encoding.jl")
include("data_integrity.jl")

# label.jl
export generate_neuropal_json
# data_integrity.jl
export check_h5_data_integrity

end # module WormWideWebData
