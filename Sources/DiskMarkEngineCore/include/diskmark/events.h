#pragma once

#include "diskmark/engine.h"

#include <string>
#include <string_view>

namespace diskmark {

std::string phaseEvent(std::string_view phase, std::string_view message);
std::string runEvent(const Job& job);
std::string progressEvent(const Job& job, std::uint64_t elapsedMs, std::uint64_t bytes);
std::string intervalEvent(int secondsRemaining);
std::string resultEvent(const JobResult& result);
std::string doneEvent(bool ok = true);
std::string errorEvent(std::string_view code, std::string_view message);

}  // namespace diskmark
