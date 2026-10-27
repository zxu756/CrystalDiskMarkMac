#include "diskmark/test_file.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <iomanip>
#include <random>
#include <sstream>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>
#include <vector>

namespace diskmark {
namespace {

constexpr std::uint64_t kFreeSpaceMargin = 512ULL * 1024 * 1024;
constexpr std::size_t kFillBufferSize = 1024 * 1024;

[[noreturn]] void fail(const std::string& code, const std::string& message) {
    throw EngineError(code, message);
}

std::string errnoMessage(const std::string& prefix) {
    return prefix + ": " + std::strerror(errno);
}

std::string markerContent() {
    std::random_device device;
    std::mt19937_64 generator(device());
    std::ostringstream output;
    output << "pid=" << getpid() << "\n";
    output << "uuid=" << std::hex << std::setw(16) << std::setfill('0') << generator() << "\n";
    return output.str();
}

void writeAll(int fd, const std::string& text) {
    std::size_t written = 0;
    while (written < text.size()) {
        const ssize_t result = write(fd, text.data() + written, text.size() - written);
        if (result < 0) {
            if (errno == EINTR) {
                continue;
            }
            fail("create_failed", errnoMessage("write marker"));
        }
        written += static_cast<std::size_t>(result);
    }
}

}  // namespace

TestFile::TestFile(const Config& config) : config_(config) {}

TestFile::~TestFile() {
    try {
        cleanup();
    } catch (...) {
    }
}

std::string TestFile::markerPath() const {
    return directory_ + "/.crystaldiskmark-mac-session";
}

void TestFile::create() {
    struct stat targetStat {};
    if (stat(config_.target.c_str(), &targetStat) != 0 || !S_ISDIR(targetStat.st_mode)) {
        fail("target_not_writable", "target is not a writable directory: " + config_.target);
    }

    struct statvfs filesystem {};
    if (statvfs(config_.target.c_str(), &filesystem) != 0) {
        fail("target_not_writable", errnoMessage("statvfs"));
    }

    const std::uint64_t available =
        static_cast<std::uint64_t>(filesystem.f_bavail) *
        static_cast<std::uint64_t>(filesystem.f_frsize);
    if (available < config_.fileSizeBytes ||
        available - config_.fileSizeBytes < kFreeSpaceMargin) {
        fail("insufficient_space", "not enough free space for the test file and safety margin");
    }

    std::string pattern = config_.target + "/CrystalDiskMarkMac-XXXXXX";
    std::vector<char> buffer(pattern.begin(), pattern.end());
    buffer.push_back('\0');
    char* created = mkdtemp(buffer.data());
    if (created == nullptr) {
        fail("create_failed", errnoMessage("mkdtemp"));
    }
    directory_ = created;
    path_ = directory_ + "/test.tmp";

    const int marker = open(markerPath().c_str(), O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (marker < 0) {
        cleanup();
        fail("create_failed", errnoMessage("open marker"));
    }
    writeAll(marker, markerContent());
    close(marker);

    fd_ = open(path_.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd_ < 0) {
        cleanup();
        fail("create_failed", errnoMessage("open test file"));
    }

    (void)fcntl(fd_, F_NOCACHE, 1);

    if (ftruncate(fd_, static_cast<off_t>(config_.fileSizeBytes)) != 0) {
        cleanup();
        fail("create_failed", errnoMessage("ftruncate"));
    }

    size_ = config_.fileSizeBytes;
}

void TestFile::fill() {
    if (fd_ < 0) {
        fail("not_created", "test file has not been created");
    }

    std::vector<char> buffer(kFillBufferSize);
    std::uint64_t offset = 0;
    while (offset < size_) {
        const std::size_t chunk = static_cast<std::size_t>(
            std::min<std::uint64_t>(buffer.size(), size_ - offset)
        );

        if (config_.dataPattern == "zero") {
            std::memset(buffer.data(), 0, chunk);
        } else {
            arc4random_buf(buffer.data(), chunk);
        }

        std::size_t written = 0;
        while (written < chunk) {
            const ssize_t result = pwrite(
                fd_,
                buffer.data() + written,
                chunk - written,
                static_cast<off_t>(offset + written)
            );
            if (result < 0) {
                if (errno == EINTR) {
                    continue;
                }
                fail("fill_failed", errnoMessage("pwrite"));
            }
            written += static_cast<std::size_t>(result);
        }
        offset += chunk;
    }
}

void TestFile::fsyncForReads() {
    if (fd_ >= 0 && fsync(fd_) != 0) {
        fail("fsync_failed", errnoMessage("fsync"));
    }
}

void TestFile::cleanup() {
    if (fd_ >= 0) {
        close(fd_);
        fd_ = -1;
    }
    if (!path_.empty()) {
        unlink(path_.c_str());
    }
    if (!directory_.empty()) {
        unlink(markerPath().c_str());
        rmdir(directory_.c_str());
    }
    path_.clear();
    directory_.clear();
    size_ = 0;
}

void cleanupStaleSessions(const std::string& target, int olderThanHours) {
    std::error_code error;
    const auto threshold = std::filesystem::file_time_type::clock::now() -
        std::chrono::hours(olderThanHours);

    for (const auto& entry : std::filesystem::directory_iterator(target, error)) {
        if (error) {
            return;
        }
        if (!entry.is_directory()) {
            continue;
        }

        const std::string name = entry.path().filename().string();
        if (name.rfind("CrystalDiskMarkMac-", 0) != 0) {
            continue;
        }
        if (!std::filesystem::exists(entry.path() / ".crystaldiskmark-mac-session")) {
            continue;
        }

        const auto modified = entry.last_write_time(error);
        if (error) {
            error.clear();
            continue;
        }
        if (modified < threshold) {
            std::filesystem::remove_all(entry.path(), error);
            error.clear();
        }
    }
}

}  // namespace diskmark
