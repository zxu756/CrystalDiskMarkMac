#include "diskmark/config.h"

#include <cassert>
#include <cstdlib>
#include <iostream>
#include <string>
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

}  // namespace

int main() {
    testSampleConfig();
    testMultipleJobsPreserveOrder();
    testInvalidConfigs();
    testEscapeJson();

    std::cout << "engine core tests passed: " << testCount << "\n";
    return 0;
}
