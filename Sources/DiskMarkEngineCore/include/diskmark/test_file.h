#pragma once

#include "diskmark/config.h"

#include <cstdint>
#include <stdexcept>
#include <string>

namespace diskmark {

struct EngineError : std::runtime_error {
    std::string code;

    EngineError(std::string code, std::string message)
        : std::runtime_error(std::move(message)), code(std::move(code)) {}
};

class TestFile {
public:
    explicit TestFile(const Config& config);
    ~TestFile();

    TestFile(const TestFile&) = delete;
    TestFile& operator=(const TestFile&) = delete;

    void create();
    void fill();
    void fsyncForReads();
    void cleanup();

    const std::string& path() const { return path_; }
    const std::string& directory() const { return directory_; }
    std::uint64_t size() const { return size_; }
    int fd() const { return fd_; }

private:
    std::string markerPath() const;

    Config config_;
    std::string directory_;
    std::string path_;
    int fd_ = -1;
    std::uint64_t size_ = 0;
};

void cleanupStaleSessions(const std::string& target, int olderThanHours = 24);

}  // namespace diskmark
