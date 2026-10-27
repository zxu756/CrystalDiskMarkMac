#pragma once

#include "diskmark/config.h"
#include "diskmark/test_file.h"

#include <atomic>
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#include <vector>

namespace diskmark {

using EventSink = std::function<void(const std::string&)>;

struct JobResult {
    std::string testId;
    std::string label;
    std::string operation;
    int run = 0;
    bool warmup = false;
    std::uint64_t bytes = 0;
    double seconds = 0.0;
    double mbps = 0.0;
    double iops = 0.0;
    double latencyUs = 0.0;
    bool cancelled = false;
};

JobResult computeResult(
    std::uint64_t bytes,
    double seconds,
    std::uint64_t blockSizeBytes,
    const std::vector<double>& latencies
);

int effectiveWorkers(int queueDepth, int threads);

std::uint64_t chooseOffset(
    std::string_view mode,
    std::uint64_t blockIndex,
    std::uint64_t totalBlocks,
    std::uint64_t blockSizeBytes
);

JobResult runJob(
    TestFile& file,
    const Job& job,
    std::atomic<bool>& cancel,
    std::atomic<std::uint64_t>* progressBytes = nullptr,
    bool zeroFill = false
);

int runSession(const Config& config, EventSink emit);
int runSession(const Config& config, EventSink emit, std::atomic<bool>& cancel);

}  // namespace diskmark
