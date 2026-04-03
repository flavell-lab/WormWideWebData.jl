# WormWideWebData.jl

`WormWideWebData.jl` provides tools to:

- sync paper metadata from the WormWideWeb reference repository,
- download dataset bundles from Zenodo/Dryad,
- validate HDF5 dataset integrity,
- transform source files into normalized JSON/HDF5 outputs.

## Installation

From Julia:

```julia
using Pkg
Pkg.develop(path=".")
```

Or add from a remote git URL if this repository is hosted.

## Quick Start

Load metadata for papers and datasets:

```julia
using WormWideWebData

papers_data, datasets_data, dataset_types = get_activity_info()
```

Generate dataset JSON files for one paper:

```julia
using WormWideWebData

paper_id = "your_paper_id"
generate_paper_datasets_json(
    "output_json_dir",
    "paper_work_dir",
    paper_id,
    datasets_data[paper_id];
    neuropal_label=false,
    encoding_data=false,
)
```

Generate normalized Neuropal labels:

```julia
using WormWideWebData

generate_neuropal_json(
    "paper_work_dir",
    "path/to/neuropal_labels.jld2",
)
```

## Exported API

- `generate_encoding_files(path_dir_target, path_analysis_dict, path_fit_results, path_relative_encoding_strength; verbose=true)`
- `get_encoding_dictionary(...)`
- `generate_neuropal_json(path_dir_target, path_neuropal_dict, verbose=true; ...)`
- `check_h5_data_integrity(path_h5; ...)`
- `get_activity_info(repo_url=..., repo_activity_path=..., scratch_dir=...)`
- `load_dict_from_h5(path_h5)`
- `load_dict_from_json(path_json)`
- `generate_paper_datasets_json(path_dir_output, path_dir_paper, paper_id, datasets; ...)`

Most additional helpers are internal but documented in source.

## Running Tests

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

Coverage run:

```bash
julia --project -e 'using Pkg; Pkg.test(coverage=true)'
```

## System Dependencies

Some workflows rely on external command-line tools:

- `git` (reference repository sync),
- `tar` and `bunzip2` (archive extraction),
- `shasum` and `md5sum` (checksums),
- `b3sum` (BLAKE3 checksum for some preprocessing paths).

Install these tools and ensure they are available in `PATH` for full functionality.
