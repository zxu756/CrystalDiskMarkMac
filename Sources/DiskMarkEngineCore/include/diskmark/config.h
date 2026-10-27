#pragma once

#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace diskmark {

struct ConfigError : std::runtime_error {
    std::string code;

    ConfigError(std::string code, std::string message)
        : std::runtime_error(std::move(message)), code(std::move(code)) {}
};

struct Job {
    std::string id;
    std::string label;
    std::string operation;
    int run = 0;
    bool warmup = false;
    std::string mode;
    std::uint64_t blockSizeBytes = 0;
    int queueDepth = 0;
    int threads = 0;
    int durationSeconds = 0;
    int intervalAfterMs = 0;
};

struct Config {
    std::string target;
    std::uint64_t fileSizeBytes = 0;
    std::string dataPattern;
    std::vector<Job> jobs;
};

Config parseConfig(std::string_view json);
std::string escapeJson(std::string_view text);

}  // namespace diskmark
