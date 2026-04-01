module WormWideWebData

using HDF5
using JSON

include("io.jl")
include("label.jl")
include("encoding.jl")

# label.jl
export generate_neuropal_json

end # module WormWideWebData
