#include "common-whisper.h"
#include "parakeet.h"
#include "whisper.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

using Clock = std::chrono::steady_clock;

static double elapsed_ms(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}

static std::string json_escape(const std::string & value) {
    std::ostringstream output;
    for (const unsigned char character : value) {
        switch (character) {
            case '"': output << "\\\""; break;
            case '\\': output << "\\\\"; break;
            case '\n': output << "\\n"; break;
            case '\r': output << "\\r"; break;
            case '\t': output << "\\t"; break;
            default:
                if (character < 0x20) {
                    char escaped[7];
                    std::snprintf(escaped, sizeof(escaped), "\\u%04x", character);
                    output << escaped;
                } else {
                    output << character;
                }
        }
    }
    return output.str();
}

static std::vector<float> load_audio(const std::string & path) {
    std::vector<float> samples;
    std::vector<std::vector<float>> channels;
    if (!read_audio_data(path.c_str(), samples, channels, false) || samples.empty()) {
        throw std::runtime_error("failed to decode " + path);
    }
    return samples;
}

static void print_result(const std::string & path, double latency_ms, const std::string & transcript) {
    std::cout << "{\"type\":\"result\",\"path\":\"" << json_escape(path)
              << "\",\"latencyMilliseconds\":" << latency_ms << ",\"transcript\":\""
              << json_escape(transcript) << "\"}\n";
}

static int run_whisper(const std::string & model_path, bool use_gpu, int argc, char ** argv) {
    auto context_params = whisper_context_default_params();
    context_params.use_gpu = use_gpu;
    context_params.flash_attn = true;

    const auto load_start = Clock::now();
    whisper_context * context = whisper_init_from_file_with_params(model_path.c_str(), context_params);
    const double cold_load_ms = elapsed_ms(load_start);
    if (context == nullptr) {
        throw std::runtime_error("failed to load Whisper model");
    }
    std::cout << "{\"type\":\"meta\",\"coldLoadMilliseconds\":" << cold_load_ms << "}\n";

    auto run = [&](const std::string & path, bool report) {
        const auto samples = load_audio(path);
        auto params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads = 4;
        params.language = "en";
        params.no_context = true;
        params.print_progress = false;
        params.print_realtime = false;
        params.print_timestamps = false;
        params.print_special = false;

        const auto start = Clock::now();
        if (whisper_full(context, params, samples.data(), static_cast<int>(samples.size())) != 0) {
            throw std::runtime_error("Whisper inference failed for " + path);
        }
        const double latency_ms = elapsed_ms(start);
        if (report) {
            std::string transcript;
            for (int index = 0; index < whisper_full_n_segments(context); ++index) {
                transcript += whisper_full_get_segment_text(context, index);
            }
            print_result(path, latency_ms, transcript);
        }
    };

    run(argv[4], false);
    for (int index = 5; index < argc; ++index) {
        run(argv[index], true);
    }
    whisper_free(context);
    return 0;
}

static int run_parakeet(const std::string & model_path, bool use_gpu, int argc, char ** argv) {
    auto context_params = parakeet_context_default_params();
    context_params.use_gpu = use_gpu;

    const auto load_start = Clock::now();
    parakeet_context * context = parakeet_init_from_file_with_params(model_path.c_str(), context_params);
    const double cold_load_ms = elapsed_ms(load_start);
    if (context == nullptr) {
        throw std::runtime_error("failed to load Parakeet model");
    }
    std::cout << "{\"type\":\"meta\",\"coldLoadMilliseconds\":" << cold_load_ms << "}\n";

    auto run = [&](const std::string & path, bool report) {
        const auto samples = load_audio(path);
        auto params = parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY);
        params.n_threads = 4;

        const auto start = Clock::now();
        if (parakeet_full(context, params, samples.data(), static_cast<int>(samples.size())) != 0) {
            throw std::runtime_error("Parakeet inference failed for " + path);
        }
        const double latency_ms = elapsed_ms(start);
        if (report) {
            std::string transcript;
            for (int index = 0; index < parakeet_full_n_segments(context); ++index) {
                transcript += parakeet_full_get_segment_text(context, index);
            }
            print_result(path, latency_ms, transcript);
        }
    };

    run(argv[4], false);
    for (int index = 5; index < argc; ++index) {
        run(argv[index], true);
    }
    parakeet_free(context);
    return 0;
}

int main(int argc, char ** argv) {
    if (argc < 6) {
        std::cerr << "usage: whisper-cpp-harness whisper|parakeet metal|cpu model warmup.wav fixture.wav...\n";
        return 2;
    }
    const std::string family = argv[1];
    const std::string backend = argv[2];
    if (backend != "metal" && backend != "cpu") {
        std::cerr << "backend must be metal or cpu\n";
        return 2;
    }

    try {
        if (family == "whisper") {
            return run_whisper(argv[3], backend == "metal", argc, argv);
        }
        if (family == "parakeet") {
            return run_parakeet(argv[3], backend == "metal", argc, argv);
        }
        throw std::runtime_error("family must be whisper or parakeet");
    } catch (const std::exception & error) {
        std::cerr << "whisper-cpp-harness: " << error.what() << "\n";
        return 1;
    }
}
