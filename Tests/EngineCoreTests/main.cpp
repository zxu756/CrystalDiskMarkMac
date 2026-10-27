#include "diskmark/config.h"
#include "diskmark/engine.h"
#include "diskmark/events.h"
#include "diskmark/test_file.h"

#include <algorithm>
#include <atomic>
#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {

int testCount = 0;

template <typename F>
void expectThrows(const std::string& name, F&& fn) {
    try {
        fn();
    } catch (const diskmark::ConfigError&) {
        ++testCount;
        return;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << name << ": wrong exception: " << error.what() << "\n";
        std::exit(1);
    }

    std::cerr << "FAIL " << name << ": expected ConfigError\n";
    std::exit(1);
}

std::string sampleConfig() {
    return R"({
      "target": "/tmp/x",
      "fileSizeBytes": 1073741824,
      "dataPattern": "random",
      "jobs": [
        {
          "id": "a",
          "label": "A",
          "operation": "read",
          "run": 0,
          "warmup": true,
          "mode": "sequential",
          "blockSizeBytes": 1048576,
          "queueDepth": 8,
          "threads": 1,
          "durationSeconds": 5,
          "intervalAfterMs": 5000
        }
      ]
    })";
}

void testSampleConfig() {
    const auto config = diskmark::parseConfig(sampleConfig());
    assert(config.target == "/tmp/x");
    assert(config.fileSizeBytes == 1073741824ULL);
    assert(config.dataPattern == "random");
    assert(config.jobs.size() == 1);
    assert(config.jobs[0].id == "a");
    assert(config.jobs[0].label == "A");
    assert(config.jobs[0].operation == "read");
    assert(config.jobs[0].run == 0);
    assert(config.jobs[0].warmup);
    assert(config.jobs[0].mode == "sequential");
    assert(config.jobs[0].blockSizeBytes == 1048576ULL);
    assert(config.jobs[0].queueDepth == 8);
    assert(config.jobs[0].threads == 1);
    assert(config.jobs[0].durationSeconds == 5);
    assert(config.jobs[0].intervalAfterMs == 5000);
    ++testCount;
}

void testMultipleJobsPreserveOrder() {
    const std::string json = R"({
      "target": "/tmp/x",
      "fileSizeBytes": 67108864,
      "dataPattern": "zero",
      "jobs": [
        {"id":"first","label":"First","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0},
        {"id":"second","label":"Second","operation":"write","run":1,"warmup":false,"mode":"random","blockSizeBytes":8192,"queueDepth":2,"threads":1,"durationSeconds":2,"intervalAfterMs":1000}
      ]
    })";

    const auto config = diskmark::parseConfig(json);
    assert(config.jobs.size() == 2);
    assert(config.jobs[0].id == "first");
    assert(config.jobs[1].id == "second");
    assert(config.jobs[1].mode == "random");
    assert(config.jobs[1].intervalAfterMs == 1000);
    ++testCount;
}

void testInvalidConfigs() {
    expectThrows("missing target", [] {
        diskmark::parseConfig(R"({"fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("empty jobs", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[]})");
    });
    expectThrows("zero file size", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":0,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("unknown data pattern", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"compressible","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("zero block size", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":0,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("zero duration", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":0,"intervalAfterMs":0}]})");
    });
    expectThrows("zero queue", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":0,"threads":1,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("zero threads", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":0,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("concurrency above cap", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":32,"threads":16,"durationSeconds":1,"intervalAfterMs":0}]})");
    });
    expectThrows("malformed json", [] {
        diskmark::parseConfig(R"({"target":)");
    });
    expectThrows("trailing garbage", [] {
        diskmark::parseConfig(sampleConfig() + "garbage");
    });
    expectThrows("unknown top-level key", [] {
        diskmark::parseConfig(R"({"target":"/tmp/x","fileSizeBytes":1,"dataPattern":"random","jobs":[{"id":"a","label":"A","operation":"read","run":0,"warmup":true,"mode":"sequential","blockSizeBytes":4096,"queueDepth":1,"threads":1,"durationSeconds":1,"intervalAfterMs":0}],"extra":true})");
    });
}

void testEscapeJson() {
    assert(diskmark::escapeJson("a\"b\\c\n") == "a\\\"b\\\\c\\n");
    ++testCount;
}

std::string makeTempDirectory() {
    std::string pattern = "/tmp/cdm-engine-test-XXXXXX";
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    char* result = mkdtemp(buffer.data());
    assert(result != nullptr);
    return std::string(result);
}

diskmark::Config configFor(const std::string& target, std::uint64_t size, const std::string& pattern) {
    diskmark::Config config;
    config.target = target;
    config.fileSizeBytes = size;
    config.dataPattern = pattern;
    return config;
}

template <typename F>
void expectEngineThrows(const std::string& name, F&& fn) {
    try {
        fn();
    } catch (const diskmark::EngineError&) {
        ++testCount;
        return;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << name << ": wrong exception: " << error.what() << "\n";
        std::exit(1);
    }

    std::cerr << "FAIL " << name << ": expected EngineError\n";
    std::exit(1);
}

void testTestFileLifecycle() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, 64ULL * 1024 * 1024, "random");

    diskmark::TestFile file(config);
    file.create();
    file.fill();
    file.fsyncForReads();

    assert(file.size() == config.fileSizeBytes);
    assert(std::filesystem::exists(file.path()));
    assert(std::filesystem::exists(file.directory() + "/.crystaldiskmark-mac-session"));

    const std::string directory = file.directory();
    file.cleanup();
    assert(!std::filesystem::exists(directory));
    file.cleanup();

    std::filesystem::remove_all(target);
    ++testCount;
}

void testTestFileRejectsFileTarget() {
    const std::string target = makeTempDirectory();
    const std::string filePath = target + "/not-a-directory";
    std::ofstream(filePath).put('x');

    const auto config = configFor(filePath, 1ULL * 1024 * 1024, "random");
    expectEngineThrows("file target", [&] {
        diskmark::TestFile file(config);
        file.create();
    });

    std::filesystem::remove_all(target);
}

void testTestFileRejectsHugeRequest() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, UINT64_MAX / 2, "random");
    expectEngineThrows("insufficient space", [&] {
        diskmark::TestFile file(config);
        file.create();
    });
    std::filesystem::remove_all(target);
}

diskmark::Job makeJob(
    const std::string& operation,
    const std::string& mode,
    std::uint64_t blockSize,
    int queueDepth,
    int threads,
    int durationSeconds
) {
    diskmark::Job job;
    job.id = "test";
    job.label = "Test";
    job.operation = operation;
    job.mode = mode;
    job.blockSizeBytes = blockSize;
    job.queueDepth = queueDepth;
    job.threads = threads;
    job.durationSeconds = durationSeconds;
    return job;
}

void testComputeResult() {
    const auto result = diskmark::computeResult(1'000'000, 1.0, 4'096, {100.0, 200.0});
    assert(std::abs(result.mbps - 1.0) < 1e-9);
    assert(std::abs(result.iops - 244.140625) < 1e-9);
    assert(std::abs(result.latencyUs - 150.0) < 1e-9);
    ++testCount;
}

void testEffectiveWorkers() {
    assert(diskmark::effectiveWorkers(8, 1) == 8);
    assert(diskmark::effectiveWorkers(1, 1) == 1);
    assert(diskmark::effectiveWorkers(32, 16) == 128);
    ++testCount;
}

void testOffsetBounds() {
    for (std::uint64_t i = 0; i < 10'000; ++i) {
        const std::uint64_t offset = diskmark::chooseOffset("random", i, 16, 4'096);
        assert(offset < 16 * 4'096);
        assert(offset % 4'096 == 0);
    }
    assert(diskmark::chooseOffset("sequential", 17, 16, 4'096) == 4'096);
    ++testCount;
}

void testSequentialRead() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, 64ULL * 1024 * 1024, "random");
    diskmark::TestFile file(config);
    file.create();
    file.fill();
    file.fsyncForReads();

    std::atomic<bool> cancel{false};
    const auto result = diskmark::runJob(
        file,
        makeJob("read", "sequential", 1ULL * 1024 * 1024, 1, 1, 1),
        cancel
    );

    assert(result.bytes > 0);
    assert(result.mbps > 0);
    assert(result.iops > 0);
    assert(!result.cancelled);

    file.cleanup();
    std::filesystem::remove_all(target);
    ++testCount;
}

void testRandomRead() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, 64ULL * 1024 * 1024, "random");
    diskmark::TestFile file(config);
    file.create();
    file.fill();
    file.fsyncForReads();

    std::atomic<bool> cancel{false};
    const auto result = diskmark::runJob(
        file,
        makeJob("read", "random", 4'096, 4, 1, 1),
        cancel
    );

    assert(result.bytes > 0);
    assert(result.mbps > 0);
    assert(!result.cancelled);

    file.cleanup();
    std::filesystem::remove_all(target);
    ++testCount;
}

void testSequentialWrite() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, 64ULL * 1024 * 1024, "random");
    diskmark::TestFile file(config);
    file.create();
    file.fill();
    file.fsyncForReads();

    std::atomic<bool> cancel{false};
    const auto result = diskmark::runJob(
        file,
        makeJob("write", "sequential", 1ULL * 1024 * 1024, 1, 1, 1),
        cancel
    );

    assert(result.bytes > 0);
    assert(result.mbps > 0);
    assert(!result.cancelled);

    file.cleanup();
    std::filesystem::remove_all(target);
    ++testCount;
}

void testCancellation() {
    const std::string target = makeTempDirectory();
    const auto config = configFor(target, 64ULL * 1024 * 1024, "random");
    diskmark::TestFile file(config);
    file.create();
    file.fill();
    file.fsyncForReads();

    std::atomic<bool> cancel{false};
    std::thread stopper([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        cancel = true;
    });

    const auto result = diskmark::runJob(
        file,
        makeJob("read", "sequential", 1ULL * 1024 * 1024, 1, 1, 5),
        cancel
    );
    stopper.join();

    assert(result.cancelled);
    assert(result.bytes > 0);

    file.cleanup();
    std::filesystem::remove_all(target);
    ++testCount;
}

bool containsEvent(const std::vector<std::string>& events, const std::string& name) {
    return std::any_of(events.begin(), events.end(), [&](const std::string& event) {
        return event.find("\"event\":\"" + name + "\"") != std::string::npos;
    });
}

std::string findEvent(const std::vector<std::string>& events, const std::string& name) {
    const auto it = std::find_if(events.begin(), events.end(), [&](const std::string& event) {
        return event.find("\"event\":\"" + name + "\"") != std::string::npos;
    });
    assert(it != events.end());
    return *it;
}

void assertNoSessionDirectories(const std::string& target) {
    for (const auto& entry : std::filesystem::directory_iterator(target)) {
        const std::string name = entry.path().filename().string();
        assert(name.rfind("CrystalDiskMarkMac-", 0) != 0);
    }
}

void testRunSession() {
    const std::string target = makeTempDirectory();
    auto config = configFor(target, 16ULL * 1024 * 1024, "random");
    auto job = makeJob("read", "sequential", 1ULL * 1024 * 1024, 1, 1, 1);
    job.warmup = true;
    config.jobs.push_back(job);

    std::mutex mutex;
    std::vector<std::string> events;
    const auto sink = [&](const std::string& line) {
        std::lock_guard<std::mutex> lock(mutex);
        events.push_back(line);
    };

    const int code = diskmark::runSession(config, sink);
    assert(code == 0);
    assert(containsEvent(events, "phase"));
    assert(containsEvent(events, "run"));
    assert(containsEvent(events, "progress"));
    assert(containsEvent(events, "result"));
    assert(containsEvent(events, "done"));

    const std::string result = findEvent(events, "result");
    assert(result.find("\"test\":\"test\"") != std::string::npos);
    assert(result.find("\"operation\":\"read\"") != std::string::npos);
    assert(result.find("\"run\":0") != std::string::npos);
    assert(result.find("\"warmup\":true") != std::string::npos);
    assert(result.find("\"mbps\":") != std::string::npos);
    assert(result.find("\"iops\":") != std::string::npos);
    assert(result.find("\"latencyUs\":") != std::string::npos);

    assertNoSessionDirectories(target);
    std::filesystem::remove_all(target);
    ++testCount;
}

void testIntervalEvents() {
    const std::string target = makeTempDirectory();
    auto config = configFor(target, 16ULL * 1024 * 1024, "random");
    auto job = makeJob("read", "sequential", 1ULL * 1024 * 1024, 1, 1, 1);
    job.intervalAfterMs = 1'000;
    config.jobs.push_back(job);

    std::mutex mutex;
    std::vector<std::string> events;
    const auto sink = [&](const std::string& line) {
        std::lock_guard<std::mutex> lock(mutex);
        events.push_back(line);
    };

    const int code = diskmark::runSession(config, sink);
    assert(code == 0);
    assert(containsEvent(events, "interval"));
    assert(containsEvent(events, "done"));
    assertNoSessionDirectories(target);
    std::filesystem::remove_all(target);
    ++testCount;
}

void testCancelledSession() {
    const std::string target = makeTempDirectory();
    auto config = configFor(target, 16ULL * 1024 * 1024, "random");
    config.jobs.push_back(makeJob("read", "sequential", 1ULL * 1024 * 1024, 1, 1, 5));

    std::mutex mutex;
    std::vector<std::string> events;
    const auto sink = [&](const std::string& line) {
        std::lock_guard<std::mutex> lock(mutex);
        events.push_back(line);
    };

    std::atomic<bool> cancel{false};
    std::thread stopper([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        cancel = true;
    });

    const int code = diskmark::runSession(config, sink, cancel);
    stopper.join();

    assert(code == 130);
    assert(containsEvent(events, "error"));
    assert(findEvent(events, "error").find("\"code\":\"cancelled\"") != std::string::npos);
    assertNoSessionDirectories(target);
    std::filesystem::remove_all(target);
    ++testCount;
}

void testEventHelpers() {
    assert(diskmark::errorEvent("bad", "oops").find("\"event\":\"error\"") != std::string::npos);
    assert(diskmark::doneEvent(true).find("\"ok\":true") != std::string::npos);
    assert(diskmark::intervalEvent(3).find("\"secondsRemaining\":3") != std::string::npos);
    ++testCount;
}

void testStaleCleanup() {
    const std::string target = makeTempDirectory();
    const std::string oldDirectory = target + "/CrystalDiskMarkMac-old";
    const std::string newDirectory = target + "/CrystalDiskMarkMac-new";
    const std::string unmarkedDirectory = target + "/CrystalDiskMarkMac-unmarked";

    std::filesystem::create_directories(oldDirectory);
    std::filesystem::create_directories(newDirectory);
    std::filesystem::create_directories(unmarkedDirectory);
    std::ofstream(oldDirectory + "/.crystaldiskmark-mac-session") << "old";
    std::ofstream(newDirectory + "/.crystaldiskmark-mac-session") << "new";

    struct timespec times[2];
    times[0].tv_sec = std::time(nullptr) - 25 * 3600;
    times[0].tv_nsec = 0;
    times[1] = times[0];
    assert(utimensat(AT_FDCWD, oldDirectory.c_str(), times, 0) == 0);

    diskmark::cleanupStaleSessions(target, 24);
    assert(!std::filesystem::exists(oldDirectory));
    assert(std::filesystem::exists(newDirectory));
    assert(std::filesystem::exists(unmarkedDirectory));

    std::filesystem::remove_all(target);
    ++testCount;
}

}  // namespace

int main() {
    testSampleConfig();
    testMultipleJobsPreserveOrder();
    testInvalidConfigs();
    testEscapeJson();
    testTestFileLifecycle();
    testTestFileRejectsFileTarget();
    testTestFileRejectsHugeRequest();
    testStaleCleanup();
    testComputeResult();
    testEffectiveWorkers();
    testOffsetBounds();
    testSequentialRead();
    testRandomRead();
    testSequentialWrite();
    testCancellation();
    testRunSession();
    testIntervalEvents();
    testCancelledSession();
    testEventHelpers();

    std::cout << "engine core tests passed: " << testCount << "\n";
    return 0;
}
