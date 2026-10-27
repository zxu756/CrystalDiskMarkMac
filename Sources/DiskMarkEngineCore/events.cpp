#include "diskmark/events.h"

#include <iomanip>
#include <sstream>

namespace diskmark {
namespace {

const char* boolText(bool value) {
    return value ? "true" : "false";
}

}  // namespace

std::string phaseEvent(std::string_view phase, std::string_view message) {
    std::ostringstream output;
    output << "{\"event\":\"phase\",\"phase\":\"" << escapeJson(phase)
           << "\",\"message\":\"" << escapeJson(message) << "\"}";
    return output.str();
}

std::string runEvent(const Job& job) {
    std::ostringstream output;
    output << "{\"event\":\"run\",\"test\":\"" << escapeJson(job.id)
           << "\",\"label\":\"" << escapeJson(job.label)
           << "\",\"operation\":\"" << escapeJson(job.operation)
           << "\",\"run\":" << job.run
           << ",\"warmup\":" << boolText(job.warmup)
           << ",\"intervalAfterMs\":" << job.intervalAfterMs
           << "}";
    return output.str();
}

std::string progressEvent(const Job& job, std::uint64_t elapsedMs, std::uint64_t bytes) {
    std::ostringstream output;
    output << "{\"event\":\"progress\",\"test\":\"" << escapeJson(job.id)
           << "\",\"operation\":\"" << escapeJson(job.operation)
           << "\",\"elapsedMs\":" << elapsedMs
           << ",\"bytes\":" << bytes
           << "}";
    return output.str();
}

std::string intervalEvent(int secondsRemaining) {
    std::ostringstream output;
    output << "{\"event\":\"interval\",\"secondsRemaining\":" << secondsRemaining << "}";
    return output.str();
}

std::string resultEvent(const JobResult& result) {
    std::ostringstream output;
    output << std::fixed << std::setprecision(6);
    output << "{\"event\":\"result\",\"test\":\"" << escapeJson(result.testId)
           << "\",\"operation\":\"" << escapeJson(result.operation)
           << "\",\"run\":" << result.run
           << ",\"warmup\":" << boolText(result.warmup)
           << ",\"mbps\":" << result.mbps
           << ",\"iops\":" << result.iops
           << ",\"latencyUs\":" << result.latencyUs
           << ",\"cancelled\":" << boolText(result.cancelled)
           << "}";
    return output.str();
}

std::string doneEvent(bool ok) {
    std::ostringstream output;
    output << "{\"event\":\"done\",\"ok\":" << boolText(ok) << "}";
    return output.str();
}

std::string errorEvent(std::string_view code, std::string_view message) {
    std::ostringstream output;
    output << "{\"event\":\"error\",\"code\":\"" << escapeJson(code)
           << "\",\"message\":\"" << escapeJson(message) << "\"}";
    return output.str();
}

}  // namespace diskmark
