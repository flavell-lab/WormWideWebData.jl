using Test
using WormWideWebData
using HTTP
using Sockets
using HDF5
using JLD2
using JSON

function with_local_http_server(f::Function, handler::Function)
    server = HTTP.serve!(handler, ip"127.0.0.1", 0; verbose = false)

    try
        (_, raw_port) = getsockname(getfield(server.listener, :server))
        port = Int(raw_port)
        sleep(0.05)
        return f("http://127.0.0.1:$port")
    finally
        close(server)
    end
end

function write_core_fixture_h5(path_h5::AbstractString)
    a = sqrt(0.5)
    h5open(path_h5, "w") do file
        timing = create_group(file, "timing")
        timing["timestamp_confocal"] = [0.0, 1.0]

        behavior = create_group(file, "behavior")
        behavior["angular_velocity"] = [0.25, -0.25]
        behavior["head_angle"] = [0.5, -0.5]
        behavior["velocity"] = [-1.0, 1.0]
        behavior["reversal_events"] = [0, 1]

        gcamp = create_group(file, "gcamp")
        gcamp["trace_array"] = [-a a; a -a]
        gcamp["trace_array_original"] = [10.0 11.0; 12.0 13.0]
    end

    return path_h5
end

function with_fake_b3sum(f::Function)
    mktempdir() do bindir
        path_b3sum = joinpath(bindir, "b3sum")
        open(path_b3sum, "w") do io
            write(io, "#!/bin/sh\n")
            write(io, string("shasum -a 256 \"", '$', "1\"\n"))
        end
        chmod(path_b3sum, 0o755)

        path_original = get(ENV, "PATH", "")
        ENV["PATH"] = string(bindir, ":", path_original)
        try
            return f()
        finally
            ENV["PATH"] = path_original
        end
    end
end

@testset "WormWideWebData" begin
    @testset "compute_mean_timestep" begin
        ts = [0.0, 1.0, 2.0, 10.0, 11.0]
        @test WormWideWebData.compute_mean_timestep(ts) == 1.0
        @test_throws AssertionError WormWideWebData.compute_mean_timestep(ts, 0)
    end

    @testset "parse_event_str" begin
        @test WormWideWebData.parse_event_str("stim=[1,2],rev=[3]") ==
              [["stim", 1], ["stim", 2], ["rev", 3]]
        @test WormWideWebData.parse_event_str("stim=[ ],rev=[4]") == [["rev", 4]]
        @test WormWideWebData.parse_event_str("no events here") == []
    end

    @testset "save/load dict helpers" begin
        mktempdir() do tmp
            dict =
                Dict("scalar" => 1.5, "vector" => [1, 2, 3], "nested" => Dict("value" => 7))
            metadata = Dict("source" => "unit-test")

            WormWideWebData.save_dict_to_h5_json(
                tmp,
                "roundtrip",
                dict;
                metadata = metadata,
            )

            path_h5 = joinpath(tmp, "roundtrip.h5")
            path_json = joinpath(tmp, "roundtrip.json")

            @test isfile(path_h5)
            @test isfile(path_json)

            loaded_h5 = WormWideWebData.load_dict_from_h5(path_h5).data
            loaded_json = WormWideWebData.load_dict_from_json(path_json).data

            @test loaded_h5["scalar"] == 1.5
            @test loaded_h5["nested"]["value"] == 7
            @test loaded_json["scalar"] == 1.5
            @test loaded_json["nested"]["value"] == 7

            @test_throws Exception WormWideWebData.save_dict_to_h5_json(
                tmp,
                "nan_disallowed",
                Dict("x" => NaN);
                allow_nan = false,
            )

            @test_throws ErrorException WormWideWebData.unarchive(
                joinpath(tmp, "unsupported.zip"),
            )
        end
    end

    @testset "dataset dict and integrity checks" begin
        mktempdir() do tmp
            path_h5 = write_core_fixture_h5(joinpath(tmp, "dataset.h5"))

            dict_output = WormWideWebData.get_dataset_dict(
                path_h5;
                θh_pos_is_ventral = true,
                h5_checksum = "abc123",
                source_filename = "dataset.h5",
                uid = "uid-1",
                paper_id = "paper-a",
                dataset_type = ["calcium", "behavior"],
                dict_encoding = Dict("score" => 42),
                dict_label = Dict("R1" => Dict("label" => "AVA")),
                events_str = "stim=[1,2],rev=[3]",
            )

            @test dict_output["metadata"]["checksum_h5"] == "abc123"
            @test dict_output["metadata"]["source_filename"] == "dataset.h5"
            @test dict_output["metadata"]["paper_id"] == "paper-a"
            @test dict_output["metadata"]["uid"] == "uid-1"
            @test dict_output["metadata"]["dataset_type"] == ["calcium", "behavior"]
            @test dict_output["timing"]["mean_timestep"] == 1.0
            @test dict_output["timing"]["max_t"] == 2
            @test dict_output["timing"]["event"] == [["stim", 1], ["stim", 2], ["rev", 3]]
            @test dict_output["behavior"]["head_angle"] == [-0.5, 0.5]
            @test dict_output["behavior"]["angular_velocity"] == [-0.25, 0.25]
            @test dict_output["gcamp"]["trace_array_original"] == [10.0 12.0; 11.0 13.0]
            @test dict_output["encoding"]["score"] == 42
            @test dict_output["label"]["R1"]["label"] == "AVA"

            trace_array = [1.0 2.0 3.0; 3.0 2.0 1.0]
            behavior = [1.0, 2.0, 3.0]
            @test WormWideWebData.neuron_behavior_correlation(trace_array, behavior, 0.5) ==
                  1

            @test isnothing(WormWideWebData.check_h5_data_integrity(path_h5))
            @test isnothing(
                WormWideWebData.check_h5_data_integrity(
                    path_h5;
                    check_velocity_cor = true,
                    check_velocity_cor_threshold = 0.9,
                    check_velocity_cor_count = 1,
                ),
            )
            @test_throws AssertionError WormWideWebData.check_h5_data_integrity(
                path_h5;
                check_velocity_cor = true,
                check_velocity_cor_threshold = 0.9,
                check_velocity_cor_count = 2,
            )

            good_checksum = WormWideWebData.sha256(path_h5)
            datasets = [
                Dict(
                    "uid" => "uid-1",
                    "filename" => "dataset.h5",
                    "checksum" => good_checksum,
                ),
            ]
            @test isnothing(WormWideWebData.check_paper_h5_datasets(datasets, tmp))

            bad_datasets = [
                Dict(
                    "uid" => "uid-1",
                    "filename" => "dataset.h5",
                    "checksum" => "bad-checksum",
                ),
            ]
            @test_throws AssertionError WormWideWebData.check_paper_h5_datasets(
                bad_datasets,
                tmp,
            )
        end
    end

    @testset "file checksum helpers" begin
        mktempdir() do tmp
            write(joinpath(tmp, "b.txt"), "bbb")
            write(joinpath(tmp, "a.txt"), "aaa")
            write(joinpath(tmp, "c.dat"), "ccc")

            txt_hashes = WormWideWebData.get_file_checksums(
                tmp;
                ext = ".TXT",
                f_checksum = path -> read(path, String),
            )
            @test [row.filename for row in txt_hashes] == ["a.txt", "b.txt"]
            @test [row.checksum for row in txt_hashes] == ["aaa", "bbb"]

            all_hashes = WormWideWebData.get_file_checksums(
                tmp;
                f_checksum = path -> read(path, String),
            )
            @test [row.filename for row in all_hashes] == ["a.txt", "b.txt", "c.dat"]
            @test [row.checksum for row in all_hashes] == ["aaa", "bbb", "ccc"]

            path_csv_header = joinpath(tmp, "checksums_with_header.csv")
            out_header = WormWideWebData.write_file_checksums_to_csv(
                tmp,
                path_csv_header;
                ext = ".txt",
                f_checksum = WormWideWebData.sha256,
                header = true,
            )
            @test out_header == path_csv_header

            txt_hashes_sha = WormWideWebData.get_file_checksums(
                tmp;
                ext = ".txt",
                f_checksum = WormWideWebData.sha256,
            )
            expected_lines = ["$(row.filename),$(row.checksum)" for row in txt_hashes_sha]
            lines_header = readlines(path_csv_header)
            @test lines_header[1] == "filename,sha256"
            @test lines_header[2:end] == expected_lines

            path_csv_no_header = joinpath(tmp, "checksums_no_header.csv")
            out_no_header = WormWideWebData.write_file_checksums_to_csv(
                tmp,
                path_csv_no_header;
                ext = ".txt",
                f_checksum = WormWideWebData.sha256,
                header = false,
            )
            @test out_no_header == path_csv_no_header
            @test readlines(path_csv_no_header) == expected_lines
        end
    end

    @testset "download_file" begin
        mktempdir() do tmp
            with_local_http_server(
                req -> begin
                    if HTTP.header(req, "Authorization") == "Bearer token"
                        return HTTP.Response(200, "payload")
                    end
                    return HTTP.Response(401, "unauthorized")
                end,
            ) do base_url
                path_save = joinpath(tmp, "protected.bin")
                WormWideWebData.download_file(
                    "$base_url/protected",
                    path_save;
                    headers = Pair{String,String}["Authorization"=>"Bearer token"],
                    verbose = false,
                    checksum = "payload",
                    f_checksum = path -> read(path, String),
                )
                @test read(path_save, String) == "payload"
            end

            with_local_http_server(req -> HTTP.Response(200, "open-data")) do base_url
                path_save = joinpath(tmp, "public.bin")
                WormWideWebData.download_file(
                    "$base_url/public",
                    path_save;
                    verbose = false,
                )
                @test read(path_save, String) == "open-data"
            end

            with_local_http_server(req -> HTTP.Response(200, "bad-data")) do base_url
                path_save = joinpath(tmp, "bad.bin")
                @test_throws ErrorException WormWideWebData.download_file(
                    "$base_url/bad",
                    path_save;
                    verbose = false,
                    checksum = "expected-good-data",
                    f_checksum = path -> read(path, String),
                )
            end
        end
    end

    @testset "check_dataset_type" begin
        papers_ok = Dict(
            "paper-a" => [
                Dict("uid" => "uid-1", "type" => "calcium"),
                Dict("uid" => "uid-2", "type" => "calcium,behavior"),
            ],
        )
        dataset_types = Dict(
            "paper-a" => [Dict("id" => "calcium")],
            "common" => [Dict("id" => "behavior")],
        )

        @test isnothing(WormWideWebData.check_dataset_type(papers_ok, dataset_types))

        papers_bad = Dict("paper-a" => [Dict("uid" => "uid-3", "type" => "invalid-type")])
        err = nothing
        try
            WormWideWebData.check_dataset_type(papers_bad, dataset_types)
        catch e
            err = e
        end

        @test err isa AssertionError
        @test occursin("paper-a|uid-3", sprint(showerror, err))
    end

    @testset "get_encoding_dictionary" begin
        theta_key = "\u03b8h"
        theta_dorsal_key = "\u03b8h_dorsal"

        neuron_categorization = Dict(
            "1" => Dict(
                "all" => [1, 2],
                "v" => Dict("fwd" => [1], "rev" => Int[]),
                theta_key => Dict("dorsal" => [2], "ventral" => Int[]),
                "P" => Dict("act" => Int[], "inh" => Int[]),
            ),
            "2" => Dict(
                "all" => [1],
                "v" => Dict("fwd" => Int[], "rev" => [2]),
                theta_key => Dict("dorsal" => Int[], "ventral" => Int[]),
                "P" => Dict("act" => [1], "inh" => Int[]),
            ),
        )

        encoding_changes_corrected =
            Dict("1" => Dict("all" => [1]), "2" => Dict("all" => [2]))

        tuning_strength = Dict(
            "1" => Dict(
                "1" => Dict("v_fwd" => 1.0, theta_dorsal_key => 0.0, "P_pos" => 0.5),
                "2" => Dict("v_fwd" => 0.1, theta_dorsal_key => 0.7, "P_pos" => 0.3),
            ),
            "2" => Dict(
                "1" => Dict("v_fwd" => 1.2, theta_dorsal_key => 0.0, "P_pos" => 0.2),
                "2" => Dict("v_fwd" => 0.2, theta_dorsal_key => 0.9, "P_pos" => 0.4),
            ),
        )

        sampled_tau_vals_median = [10.0 20.0; 30.0 40.0]
        fit_ranges = [1 50; 51 100]
        relative_encoding_strength_median = Dict(
            "v" => [0.2 0.4; 0.8 1.0],
            theta_key => [0.5 0.7; 1.1 1.3],
            "P" => [0.9 1.1; 1.5 1.7],
        )

        output = WormWideWebData.get_encoding_dictionary(
            neuron_categorization,
            encoding_changes_corrected,
            tuning_strength,
            sampled_tau_vals_median,
            fit_ranges,
            relative_encoding_strength_median,
        )

        @test output["ranges"] == fit_ranges
        @test output["tau_vals"] ≈ [20.0, 20.0]
        @test output["forwardness"] ≈ [1.0, 0.2]
        @test output["dorsalness"] ≈ [0.0, 0.7]
        @test output["feedingness"] ≈ [0.2, 0.0]
        @test output["rel_enc_str_v"] ≈ [0.3, 0.8]
        @test sort(output["encoding_changing_neurons"]) == [1, 2]
    end

    @testset "label generation" begin
        mktempdir() do tmp
            with_fake_b3sum() do
                path_neuropal_dict = joinpath(tmp, "neuropal.jld2")
                jldopen(path_neuropal_dict, "w") do file
                    file["dict_neuropal_label"] =
                        Dict("uid-1" => (Dict("roi1" => "AVA"), Dict("AVA" => "roi1")))
                end

                path_json = WormWideWebData.generate_neuropal_json(
                    tmp,
                    path_neuropal_dict,
                    false;
                    json_name = "neuropal.json",
                )
                parsed = JSON.parsefile(path_json, dicttype = Dict)
                @test parsed["data"]["uid-1"]["roi_to_neuron"]["roi1"] == "AVA"
                @test parsed["data"]["uid-1"]["neuron_to_roi"]["AVA"] == "roi1"
                @test haskey(parsed["metadata"], "blake3_neuropal_dict")

                @test_throws ErrorException WormWideWebData.generate_neuropal_json(
                    tmp,
                    path_neuropal_dict,
                    false;
                    json_name = "neuropal.json",
                    overwrite = false,
                )
            end
        end
    end
end
