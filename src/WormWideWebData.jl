module WormWideWebData

using HDF5
using JSON
using JLD2

include("io.jl")
include("label.jl")
include("encoding.jl")

# label.jl
export generate_neuropal_json

end # module WormWideWebData
