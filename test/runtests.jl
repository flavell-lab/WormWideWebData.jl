using Test
using WormWideWebData
using HTTP
using Sockets

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

@testset "WormWideWebData" begin
    @testset "compute_mean_timestep" begin
        ts = [0.0, 1.0, 2.0, 10.0, 11.0]
        @test WormWideWebData.compute_mean_timestep(ts) == 1.0
        @test_throws AssertionError WormWideWebData.compute_mean_timestep(ts, 0)
    end

    @testset "save/load dict helpers" begin
        mktempdir() do tmp
            dict = Dict(
                "scalar" => 1.5,
                "vector" => [1, 2, 3],
                "nested" => Dict("value" => 7),
            )
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

            loaded_h5 = WormWideWebData.load_dict_from_h5(path_h5)
            loaded_json = WormWideWebData.load_dict_from_json(path_json)

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
                    headers = Pair{String,String}["Authorization" => "Bearer token"],
                    verbose = false,
                    checksum = "payload",
                    f_checksum = path -> read(path, String),
                )
                @test read(path_save, String) == "payload"
            end

            with_local_http_server(req -> HTTP.Response(200, "open-data")) do base_url
                path_save = joinpath(tmp, "public.bin")
                WormWideWebData.download_file("$base_url/public", path_save; verbose = false)
                @test read(path_save, String) == "open-data"
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

        encoding_changes_corrected = Dict(
            "1" => Dict("all" => [1]),
            "2" => Dict("all" => [2]),
        )

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
end
