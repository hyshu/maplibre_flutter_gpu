#include "frame/frame_metadata.hpp"

#include <rapidjson/document.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <numeric>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

extern "C" {
void* maplibre_session_create();
void maplibre_session_select(void*);
void maplibre_session_release(void*);
int maplibre_init(int, int, float, const char*);
void maplibre_set_camera_full(double, double, double, double, double);
int maplibre_is_idle();
void maplibre_frame_begin();
void maplibre_frame_end();
int maplibre_render_frame();
int maplibre_frame_get_command_stride();
const FrameMetadata* maplibre_frame_get_metadata();
void maplibre_destroy();
void maplibre_shutdown_all();
}

using Clock = std::chrono::steady_clock;

struct Sample {
    double frameMicros;
    uint64_t commands;
    uint64_t headerBytes;
    uint64_t payloadBytes;
};

static std::string loadStyle(const char* path, int copies) {
    std::ifstream input(path);
    if (!input) throw std::runtime_error("Cannot read the style fixture");
    const std::string json((std::istreambuf_iterator<char>(input)), {});
    rapidjson::Document style;
    style.Parse(json.c_str());
    if (style.HasParseError() || !style.HasMember("layers") || !style["layers"].IsArray()) {
        throw std::runtime_error("Invalid style fixture");
    }
    auto& layers = style["layers"];
    const auto originalCount = layers.Size();
    for (int copy = 1; copy < copies; ++copy) {
        for (rapidjson::SizeType index = 0; index < originalCount; ++index) {
            if (std::string(layers[index]["type"].GetString()) == "background") continue;
            rapidjson::Value layer;
            layer.CopyFrom(layers[index], style.GetAllocator());
            const auto id = std::string(layer["id"].GetString()) + "-benchmark-" + std::to_string(copy);
            layer["id"].SetString(id.c_str(), id.size(), style.GetAllocator());
            layers.PushBack(layer, style.GetAllocator());
        }
    }
    rapidjson::StringBuffer buffer;
    rapidjson::Writer<rapidjson::StringBuffer> writer(buffer);
    style.Accept(writer);

    return buffer.GetString();
}

static Sample render(int stride) {
    const auto start = Clock::now();
    maplibre_frame_begin();
    const auto status = maplibre_render_frame();
    maplibre_frame_end();
    const auto end = Clock::now();
    if (status != 0) throw std::runtime_error("Native frame rendering failed");
    const auto* metadata = maplibre_frame_get_metadata();
    if (!metadata || metadata->commandCount <= 0 || metadata->commandStride != stride) {
        throw std::runtime_error("Native frame has no valid commands");
    }
    // Payload metadata is available only for the 64-byte command layout.
    const uint64_t payloadBytes = stride == 64 ? metadata->payloadSize : 0;

    return {
        std::chrono::duration<double, std::micro>(end - start).count(),
        static_cast<uint64_t>(metadata->commandCount),
        static_cast<uint64_t>(metadata->commandCount) * stride,
        payloadBytes,
    };
}

static void moveCamera(int step) {
    constexpr int steps = 30;
    const int position = step % (steps * 2);
    const double t = position < steps ? (position + 1.0) / steps : (steps * 2 - position - 1.0) / steps;
    maplibre_set_camera_full(35.6812 + 0.0018 * t, 139.7671 + 0.0024 * t,
                            13.25 + 0.5 * t, 17 + 15 * t, 28 + 6 * t);
}

static double percentile(const std::vector<double>& sorted, double fraction) {
    return sorted[static_cast<size_t>(std::ceil(sorted.size() * fraction)) - 1];
}

int main(int argc, char** argv) {
    if (argc != 5) {
        std::cerr << "Usage: command_frame_benchmark style.json output.json layer-copies round-trips\n";
        return 64;
    }
    void* session = nullptr;
    try {
        const int copies = std::stoi(argv[3]);
        const int roundTrips = std::stoi(argv[4]);
        if (copies < 1 || roundTrips < 1) throw std::runtime_error("Counts must be positive");
        const auto style = loadStyle(argv[1], copies);
        session = maplibre_session_create();
        if (!session) throw std::runtime_error("Cannot create a native session");
        maplibre_session_select(session);
        if (maplibre_init(800, 600, 2, style.c_str()) != 0) {
            throw std::runtime_error("Cannot initialize the native map");
        }
        maplibre_set_camera_full(35.6812, 139.7671, 13.25, 17, 28);
        const int stride = maplibre_frame_get_command_stride();
        if (stride != 496 && stride != 64) throw std::runtime_error("Unsupported command layout");
        const auto deadline = Clock::now() + std::chrono::seconds(30);
        while (!maplibre_is_idle()) {
            maplibre_frame_begin();
            if (maplibre_render_frame() != 0) throw std::runtime_error("Initial rendering failed");
            maplibre_frame_end();
            if (Clock::now() > deadline) throw std::runtime_error("Map did not become idle");
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        constexpr int warmUpRoundTrips = 10;
        for (int step = 0; step < warmUpRoundTrips * 60; ++step) {
            moveCamera(step);
            render(stride);
        }
        std::vector<Sample> samples;
        samples.reserve(roundTrips * 60);
        for (int step = 0; step < roundTrips * 60; ++step) {
            moveCamera(step);
            samples.push_back(render(stride));
        }
        std::vector<double> times;
        uint64_t commands = 0, headerBytes = 0, payloadBytes = 0;
        for (const auto& sample : samples) {
            times.push_back(sample.frameMicros);
            commands += sample.commands;
            headerBytes += sample.headerBytes;
            payloadBytes += sample.payloadBytes;
        }
        std::sort(times.begin(), times.end());
        const double count = samples.size();
        std::ofstream output(argv[2]);
        if (!output) throw std::runtime_error("Cannot write benchmark results");
        output << "{\n"
               << "  \"command_stride\": " << stride << ",\n"
               << "  \"layer_copies\": " << copies << ",\n"
               << "  \"warm_up_round_trips\": " << warmUpRoundTrips << ",\n"
               << "  \"measured_round_trips\": " << roundTrips << ",\n"
               << "  \"frame_count\": " << samples.size() << ",\n"
               << "  \"mean_frame_micros\": " << std::accumulate(times.begin(), times.end(), 0.0) / count << ",\n"
               << "  \"median_frame_micros\": " << percentile(times, 0.5) << ",\n"
               << "  \"p95_frame_micros\": " << percentile(times, 0.95) << ",\n"
               << "  \"mean_command_count\": " << commands / count << ",\n"
               << "  \"mean_header_bytes\": " << headerBytes / count << ",\n"
               << "  \"mean_payload_bytes\": " << payloadBytes / count << ",\n"
               << "  \"mean_command_stream_bytes\": " << (headerBytes + payloadBytes) / count << "\n}\n";
        std::cout << "Native frame median " << percentile(times, 0.5) << " us, p95 "
                  << percentile(times, 0.95) << " us, commands " << commands / count
                  << ", command stream " << (headerBytes + payloadBytes) / count << " bytes\n";
        maplibre_destroy();
        maplibre_session_release(session);
        maplibre_shutdown_all();
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        if (session) {
            maplibre_destroy();
            maplibre_session_release(session);
        }
        maplibre_shutdown_all();
        return 1;
    }
    return 0;
}
