#include "diskmark/engine.h"
#include "diskmark/events.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <random>
#include <thread>
#include <unistd.h>
#include <vector>

namespace diskmark {
namespace {

[[noreturn]] void fail(const std::string& code, const std::string& message) {
    throw EngineError(code, message);
}

}  // namespace

JobResult computeResult(
    std::uint64_t bytes,
    double seconds,
    std::uint64_t blockSizeBytes,
    const std::vector<double>& latencies
) {
    JobResult result;
    result.bytes = bytes;
    result.seconds = seconds;

    if (seconds > 0.0) {
        result.mbps = static_cast<double>(bytes) / 1'000'000.0 / seconds;
    }
    if (blockSizeBytes > 0) {
        result.iops = result.mbps * 1'000'000.0 / static_cast<double>(blockSizeBytes);
    }
    if (!latencies.empty()) {
        double total = 0.0;
        for (const double latency : latencies) {
            total += latency;
        }
        result.latencyUs = total / static_cast<double>(latencies.size());
    }

    return result;
}

int effectiveWorkers(int queueDepth, int threads) {
    if (queueDepth <= 0 || threads <= 0) {
        return 0;
    }
    const long long requested = static_cast<long long>(queueDepth) * static_cast<long long>(threads);
    return static_cast<int>(std::min<long long>(requested, 128));
}

std::uint64_t chooseOffset(
    std::string_view mode,
    std::uint64_t blockIndex,
    std::uint64_t totalBlocks,
    std::uint64_t blockSizeBytes
) {
    if (totalBlocks == 0) {
        return 0;
    }
    (void)mode;
    return (blockIndex % totalBlocks) * blockSizeBytes;
}

JobResult runJob(
    TestFile& file,
    const Job& job,
    std::atomic<bool>& cancel,
    std::atomic<std::uint64_t>* progressBytes
) {
    if (file.fd() < 0) {
        fail("not_created", "test file is not open");
    }
    if (job.blockSizeBytes == 0) {
        fail("invalid_job", "block size must be greater than zero");
    }
    if (job.durationSeconds <= 0) {
        fail("invalid_job", "duration must be greater than zero");
    }
    if (job.operation != "read" && job.operation != "write") {
        fail("invalid_job", "operation must be read or write");
    }
    if (job.mode != "sequential" && job.mode != "random") {
        fail("invalid_job", "mode must be sequential or random");
    }

    const std::uint64_t totalBlocks = file.size() / job.blockSizeBytes;
    if (totalBlocks == 0) {
        fail("invalid_job", "test file is smaller than the block size");
    }

    const int workerCount = effectiveWorkers(job.queueDepth, job.threads);
    if (workerCount <= 0) {
        fail("invalid_job", "invalid queue/thread configuration");
    }

    std::vector<void*> buffers(static_cast<std::size_t>(workerCount), nullptr);
    for (int i = 0; i < workerCount; ++i) {
        if (posix_memalign(&buffers[static_cast<std::size_t>(i)], 4096, static_cast<std::size_t>(job.blockSizeBytes)) != 0) {
            for (void* buffer : buffers) {
                std::free(buffer);
            }
            fail("allocation_failed", "could not allocate worker buffers");
        }
        if (job.operation == "write") {
            arc4random_buf(buffers[static_cast<std::size_t>(i)], static_cast<std::size_t>(job.blockSizeBytes));
        }
    }

    std::atomic<std::uint64_t> nextBlock{0};
    std::atomic<std::uint64_t> bytesTransferred{0};
    std::atomic<bool> failed{false};
    std::atomic<bool> start{false};
    std::atomic<int> ready{0};

    std::vector<double> latencySums(static_cast<std::size_t>(workerCount), 0.0);
    std::vector<std::uint64_t> latencyCounts(static_cast<std::size_t>(workerCount), 0);

    std::vector<std::thread> workers;
    workers.reserve(static_cast<std::size_t>(workerCount));

    for (int workerIndex = 0; workerIndex < workerCount; ++workerIndex) {
        workers.emplace_back([&, workerIndex] {
            char* buffer = static_cast<char*>(buffers[static_cast<std::size_t>(workerIndex)]);
            std::mt19937_64 generator(std::random_device{}() + static_cast<std::uint64_t>(workerIndex));

            ready.fetch_add(1, std::memory_order_release);
            while (!start.load(std::memory_order_acquire)) {
                std::this_thread::yield();
            }

            const auto begin = std::chrono::steady_clock::now();
            const auto deadline = begin + std::chrono::seconds(job.durationSeconds);
            double localLatencySum = 0.0;
            std::uint64_t localLatencyCount = 0;

            while (!cancel.load(std::memory_order_relaxed) &&
                   !failed.load(std::memory_order_relaxed) &&
                   std::chrono::steady_clock::now() < deadline) {
                const std::uint64_t blockIndex =
                    job.mode == "sequential" ? nextBlock.fetch_add(1, std::memory_order_relaxed) : generator();
                const std::uint64_t offset = chooseOffset(
                    job.mode,
                    blockIndex,
                    totalBlocks,
                    job.blockSizeBytes
                );

                const auto operationStart = std::chrono::steady_clock::now();
                ssize_t transferred = 0;
                do {
                    transferred = job.operation == "read"
                        ? pread(
                              file.fd(),
                              buffer,
                              static_cast<std::size_t>(job.blockSizeBytes),
                              static_cast<off_t>(offset)
                          )
                        : pwrite(
                              file.fd(),
                              buffer,
                              static_cast<std::size_t>(job.blockSizeBytes),
                              static_cast<off_t>(offset)
                          );
                } while (transferred < 0 && errno == EINTR);
                const auto operationEnd = std::chrono::steady_clock::now();

                if (transferred < 0) {
                    failed.store(true, std::memory_order_relaxed);
                    break;
                }
                if (transferred == 0) {
                    break;
                }

                bytesTransferred.fetch_add(
                    static_cast<std::uint64_t>(transferred),
                    std::memory_order_relaxed
                );
                if (progressBytes != nullptr) {
                    progressBytes->fetch_add(
                        static_cast<std::uint64_t>(transferred),
                        std::memory_order_relaxed
                    );
                }
                localLatencySum += std::chrono::duration<double, std::micro>(
                    operationEnd - operationStart
                ).count();
                ++localLatencyCount;
            }

            latencySums[static_cast<std::size_t>(workerIndex)] = localLatencySum;
            latencyCounts[static_cast<std::size_t>(workerIndex)] = localLatencyCount;
        });
    }

    while (ready.load(std::memory_order_acquire) < workerCount) {
        std::this_thread::yield();
    }

    const auto startTime = std::chrono::steady_clock::now();
    start.store(true, std::memory_order_release);

    for (std::thread& worker : workers) {
        worker.join();
    }

    const auto endTime = std::chrono::steady_clock::now();
    const double seconds = std::chrono::duration<double>(endTime - startTime).count();

    for (void* buffer : buffers) {
        std::free(buffer);
    }

    if (failed.load(std::memory_order_relaxed)) {
        fail("io_failed", "an I/O operation failed");
    }

    double latencySum = 0.0;
    std::uint64_t latencyCount = 0;
    for (std::size_t i = 0; i < latencySums.size(); ++i) {
        latencySum += latencySums[i];
        latencyCount += latencyCounts[i];
    }

    JobResult result = computeResult(
        bytesTransferred.load(std::memory_order_relaxed),
        seconds,
        job.blockSizeBytes,
        {}
    );
    result.testId = job.id;
    result.label = job.label;
    result.operation = job.operation;
    result.run = job.run;
    result.warmup = job.warmup;
    result.cancelled = cancel.load(std::memory_order_relaxed);
    if (latencyCount > 0) {
        result.latencyUs = latencySum / static_cast<double>(latencyCount);
    }

    return result;
}

namespace {

std::atomic<bool>* gCancelFlag = nullptr;

extern "C" void handleSignal(int) {
    if (gCancelFlag != nullptr) {
        gCancelFlag->store(true, std::memory_order_relaxed);
    }
}

int runSessionImpl(const Config& config, const EventSink& emit, std::atomic<bool>& cancel) {
    gCancelFlag = &cancel;
    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    TestFile file(config);
    try {
        cleanupStaleSessions(config.target);

        emit(phaseEvent("create", "Creating test file"));
        file.create();

        emit(phaseEvent("fill", "Filling test file"));
        file.fill();

        const bool hasReadJob = std::any_of(
            config.jobs.begin(),
            config.jobs.end(),
            [](const Job& job) { return job.operation == "read"; }
        );
        if (hasReadJob) {
            file.fsyncForReads();
        }

        for (const Job& job : config.jobs) {
            if (cancel.load(std::memory_order_relaxed)) {
                emit(errorEvent("cancelled", "Cancelled"));
                file.cleanup();
                gCancelFlag = nullptr;
                return 130;
            }

            emit(runEvent(job));

            std::atomic<bool> jobDone{false};
            std::atomic<std::uint64_t> jobBytes{0};
            std::thread reporter([&] {
                const auto begin = std::chrono::steady_clock::now();
                while (!jobDone.load(std::memory_order_acquire)) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(250));
                    if (jobDone.load(std::memory_order_acquire)) {
                        break;
                    }
                    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                        std::chrono::steady_clock::now() - begin
                    ).count();
                    emit(progressEvent(
                        job,
                        static_cast<std::uint64_t>(elapsed),
                        jobBytes.load(std::memory_order_relaxed)
                    ));
                }
            });

            JobResult result;
            try {
                result = runJob(file, job, cancel, &jobBytes);
            } catch (...) {
                jobDone.store(true, std::memory_order_release);
                reporter.join();
                throw;
            }
            jobDone.store(true, std::memory_order_release);
            reporter.join();

            emit(resultEvent(result));

            if (result.cancelled || cancel.load(std::memory_order_relaxed)) {
                emit(errorEvent("cancelled", "Cancelled"));
                file.cleanup();
                gCancelFlag = nullptr;
                return 130;
            }

            if (job.intervalAfterMs > 0) {
                const int seconds = (job.intervalAfterMs + 999) / 1'000;
                for (int remaining = seconds; remaining > 0; --remaining) {
                    if (cancel.load(std::memory_order_relaxed)) {
                        emit(errorEvent("cancelled", "Cancelled"));
                        file.cleanup();
                        gCancelFlag = nullptr;
                        return 130;
                    }
                    emit(intervalEvent(remaining));
                    std::this_thread::sleep_for(std::chrono::seconds(1));
                }
            }
        }

        emit(phaseEvent("cleanup", "Removing test file"));
        file.cleanup();
        emit(doneEvent(true));
        gCancelFlag = nullptr;
        return 0;
    } catch (const EngineError& error) {
        file.cleanup();
        emit(errorEvent(error.code, error.what()));
        gCancelFlag = nullptr;
        return 3;
    } catch (const std::exception& error) {
        file.cleanup();
        emit(errorEvent("engine_failure", error.what()));
        gCancelFlag = nullptr;
        return 3;
    }
}

}  // namespace

int runSession(const Config& config, EventSink emit) {
    std::atomic<bool> cancel{false};
    return runSessionImpl(config, emit, cancel);
}

int runSession(const Config& config, EventSink emit, std::atomic<bool>& cancel) {
    return runSessionImpl(config, emit, cancel);
}

}  // namespace diskmark
