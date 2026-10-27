#include "diskmark/config.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <initializer_list>
#include <map>
#include <sstream>

namespace diskmark {
namespace {

struct JsonValue {
    enum class Type { Null, Bool, Number, String, Array, Object };

    Type type = Type::Null;
    bool boolValue = false;
    double numberValue = 0.0;
    std::string stringValue;
    std::vector<JsonValue> arrayValue;
    std::map<std::string, JsonValue> objectValue;
};

class Parser {
public:
    explicit Parser(std::string_view input) : input_(input) {}

    JsonValue parse() {
        skipWhitespace();
        JsonValue value = parseValue();
        skipWhitespace();
        if (position_ != input_.size()) {
            fail("trailing characters");
        }
        return value;
    }

private:
    std::string_view input_;
    std::size_t position_ = 0;

    [[noreturn]] void fail(const std::string& message) const {
        throw ConfigError("invalid_json", message + " at offset " + std::to_string(position_));
    }

    void skipWhitespace() {
        while (position_ < input_.size()) {
            const char c = input_[position_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++position_;
            } else {
                break;
            }
        }
    }

    char peek() const {
        if (position_ >= input_.size()) {
            fail("unexpected end of input");
        }
        return input_[position_];
    }

    char take() {
        const char c = peek();
        ++position_;
        return c;
    }

    void expect(char expected) {
        if (take() != expected) {
            fail(std::string("expected '") + expected + "'");
        }
    }

    bool consume(char expected) {
        if (position_ < input_.size() && input_[position_] == expected) {
            ++position_;
            return true;
        }
        return false;
    }

    JsonValue parseValue() {
        skipWhitespace();
        const char c = peek();
        switch (c) {
            case '{': return parseObject();
            case '[': return parseArray();
            case '"': {
                JsonValue value;
                value.type = JsonValue::Type::String;
                value.stringValue = parseString();
                return value;
            }
            case 't': return parseLiteral("true", true);
            case 'f': return parseLiteral("false", false);
            case 'n': return parseLiteral("null", false, true);
            default:
                if (c == '-' || (c >= '0' && c <= '9')) {
                    return parseNumber();
                }
                fail("unexpected value");
        }
    }

    JsonValue parseLiteral(std::string_view literal, bool boolValue, bool isNull = false) {
        if (input_.substr(position_, literal.size()) != literal) {
            fail("invalid literal");
        }
        position_ += literal.size();
        JsonValue value;
        if (isNull) {
            value.type = JsonValue::Type::Null;
        } else {
            value.type = JsonValue::Type::Bool;
            value.boolValue = boolValue;
        }
        return value;
    }

    JsonValue parseObject() {
        expect('{');
        JsonValue value;
        value.type = JsonValue::Type::Object;
        skipWhitespace();
        if (consume('}')) {
            return value;
        }

        while (true) {
            skipWhitespace();
            if (peek() != '"') {
                fail("object key must be a string");
            }
            const std::string key = parseString();
            skipWhitespace();
            expect(':');
            JsonValue member = parseValue();
            if (!value.objectValue.emplace(key, std::move(member)).second) {
                fail("duplicate key: " + key);
            }
            skipWhitespace();
            if (consume('}')) {
                break;
            }
            expect(',');
        }
        return value;
    }

    JsonValue parseArray() {
        expect('[');
        JsonValue value;
        value.type = JsonValue::Type::Array;
        skipWhitespace();
        if (consume(']')) {
            return value;
        }

        while (true) {
            value.arrayValue.push_back(parseValue());
            skipWhitespace();
            if (consume(']')) {
                break;
            }
            expect(',');
        }
        return value;
    }

    static int hexValue(char c) {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    std::uint32_t parseHex4() {
        std::uint32_t value = 0;
        for (int i = 0; i < 4; ++i) {
            const int digit = hexValue(take());
            if (digit < 0) {
                fail("invalid unicode escape");
            }
            value = (value << 4) | static_cast<std::uint32_t>(digit);
        }
        return value;
    }

    static void appendUtf8(std::string& output, std::uint32_t codepoint) {
        if (codepoint <= 0x7F) {
            output.push_back(static_cast<char>(codepoint));
        } else if (codepoint <= 0x7FF) {
            output.push_back(static_cast<char>(0xC0 | (codepoint >> 6)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else if (codepoint <= 0xFFFF) {
            output.push_back(static_cast<char>(0xE0 | (codepoint >> 12)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        } else {
            output.push_back(static_cast<char>(0xF0 | (codepoint >> 18)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3F)));
            output.push_back(static_cast<char>(0x80 | (codepoint & 0x3F)));
        }
    }

    std::string parseString() {
        expect('"');
        std::string output;
        while (true) {
            const char c = take();
            if (c == '"') {
                return output;
            }
            if (static_cast<unsigned char>(c) < 0x20) {
                fail("control character in string");
            }
            if (c != '\\') {
                output.push_back(c);
                continue;
            }

            const char escaped = take();
            switch (escaped) {
                case '"': output.push_back('"'); break;
                case '\\': output.push_back('\\'); break;
                case '/': output.push_back('/'); break;
                case 'b': output.push_back('\b'); break;
                case 'f': output.push_back('\f'); break;
                case 'n': output.push_back('\n'); break;
                case 'r': output.push_back('\r'); break;
                case 't': output.push_back('\t'); break;
                case 'u': {
                    std::uint32_t codepoint = parseHex4();
                    if (codepoint >= 0xD800 && codepoint <= 0xDBFF) {
                        if (!consume('\\') || !consume('u')) {
                            fail("missing low surrogate");
                        }
                        const std::uint32_t low = parseHex4();
                        if (low < 0xDC00 || low > 0xDFFF) {
                            fail("invalid low surrogate");
                        }
                        codepoint = 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00);
                    } else if (codepoint >= 0xDC00 && codepoint <= 0xDFFF) {
                        fail("unexpected low surrogate");
                    }
                    appendUtf8(output, codepoint);
                    break;
                }
                default: fail("invalid string escape");
            }
        }
    }

    JsonValue parseNumber() {
        const std::size_t start = position_;
        if (consume('-')) {
        }
        if (!consume('0')) {
            if (peek() < '1' || peek() > '9') {
                fail("invalid number");
            }
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9') {
                ++position_;
            }
        }
        if (consume('.')) {
            if (peek() < '0' || peek() > '9') {
                fail("invalid fraction");
            }
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9') {
                ++position_;
            }
        }
        if (position_ < input_.size() && (input_[position_] == 'e' || input_[position_] == 'E')) {
            ++position_;
            if (position_ < input_.size() && (input_[position_] == '+' || input_[position_] == '-')) {
                ++position_;
            }
            if (peek() < '0' || peek() > '9') {
                fail("invalid exponent");
            }
            while (position_ < input_.size() && input_[position_] >= '0' && input_[position_] <= '9') {
                ++position_;
            }
        }

        const std::string token(input_.substr(start, position_ - start));
        char* end = nullptr;
        const double number = std::strtod(token.c_str(), &end);
        if (end == nullptr || *end != '\0' || !std::isfinite(number)) {
            fail("invalid number");
        }

        JsonValue value;
        value.type = JsonValue::Type::Number;
        value.numberValue = number;
        return value;
    }
};

[[noreturn]] void failConfig(const std::string& message) {
    throw ConfigError("invalid_config", message);
}

const JsonValue& requireObject(const JsonValue& value, const std::string& context) {
    if (value.type != JsonValue::Type::Object) {
        failConfig(context + " must be an object");
    }
    return value;
}

const JsonValue& requireKey(const JsonValue& object, const std::string& key, const std::string& context) {
    const auto it = object.objectValue.find(key);
    if (it == object.objectValue.end()) {
        failConfig(context + " is missing '" + key + "'");
    }
    return it->second;
}

void rejectUnknownKeys(
    const JsonValue& object,
    std::initializer_list<std::string_view> allowed,
    const std::string& context
) {
    for (const auto& [key, value] : object.objectValue) {
        (void)value;
        if (std::find(allowed.begin(), allowed.end(), key) == allowed.end()) {
            failConfig(context + " has unknown key '" + key + "'");
        }
    }
}

std::string requireString(const JsonValue& value, const std::string& context) {
    if (value.type != JsonValue::Type::String) {
        failConfig(context + " must be a string");
    }
    return value.stringValue;
}

bool requireBool(const JsonValue& value, const std::string& context) {
    if (value.type != JsonValue::Type::Bool) {
        failConfig(context + " must be a boolean");
    }
    return value.boolValue;
}

double requireIntegralNumber(const JsonValue& value, const std::string& context) {
    if (value.type != JsonValue::Type::Number ||
        value.numberValue < 0 ||
        std::floor(value.numberValue) != value.numberValue) {
        failConfig(context + " must be a non-negative integer");
    }
    return value.numberValue;
}

std::uint64_t requireUInt64(const JsonValue& value, const std::string& context) {
    const double number = requireIntegralNumber(value, context);
    if (number > 9.007199254740992e15) {
        failConfig(context + " is too large");
    }
    return static_cast<std::uint64_t>(number);
}

int requireInt(const JsonValue& value, const std::string& context) {
    const double number = requireIntegralNumber(value, context);
    if (number > static_cast<double>(2147483647)) {
        failConfig(context + " is too large");
    }
    return static_cast<int>(number);
}

}  // namespace

Config parseConfig(std::string_view json) {
    const JsonValue root = Parser(json).parse();
    requireObject(root, "root");
    rejectUnknownKeys(root, {"target", "fileSizeBytes", "dataPattern", "jobs"}, "root");

    Config config;
    config.target = requireString(requireKey(root, "target", "root"), "target");
    if (config.target.empty()) {
        failConfig("target must not be empty");
    }

    config.fileSizeBytes = requireUInt64(requireKey(root, "fileSizeBytes", "root"), "fileSizeBytes");
    if (config.fileSizeBytes == 0) {
        failConfig("fileSizeBytes must be greater than zero");
    }

    config.dataPattern = requireString(requireKey(root, "dataPattern", "root"), "dataPattern");
    if (config.dataPattern != "random" && config.dataPattern != "zero") {
        failConfig("dataPattern must be 'random' or 'zero'");
    }

    const JsonValue& jobs = requireKey(root, "jobs", "root");
    if (jobs.type != JsonValue::Type::Array || jobs.arrayValue.empty()) {
        failConfig("jobs must be a non-empty array");
    }

    for (const JsonValue& item : jobs.arrayValue) {
        requireObject(item, "job");
        rejectUnknownKeys(
            item,
            {
                "id", "label", "operation", "run", "warmup", "mode",
                "blockSizeBytes", "queueDepth", "threads", "durationSeconds",
                "intervalAfterMs"
            },
            "job"
        );

        Job job;
        job.id = requireString(requireKey(item, "id", "job"), "job.id");
        job.label = requireString(requireKey(item, "label", "job"), "job.label");
        job.operation = requireString(requireKey(item, "operation", "job"), "job.operation");
        job.run = requireInt(requireKey(item, "run", "job"), "job.run");
        job.warmup = requireBool(requireKey(item, "warmup", "job"), "job.warmup");
        job.mode = requireString(requireKey(item, "mode", "job"), "job.mode");
        job.blockSizeBytes = requireUInt64(requireKey(item, "blockSizeBytes", "job"), "job.blockSizeBytes");
        job.queueDepth = requireInt(requireKey(item, "queueDepth", "job"), "job.queueDepth");
        job.threads = requireInt(requireKey(item, "threads", "job"), "job.threads");
        job.durationSeconds = requireInt(requireKey(item, "durationSeconds", "job"), "job.durationSeconds");
        job.intervalAfterMs = requireInt(requireKey(item, "intervalAfterMs", "job"), "job.intervalAfterMs");

        if (job.id.empty() || job.label.empty()) {
            failConfig("job id and label must not be empty");
        }
        if (job.operation != "read" && job.operation != "write") {
            failConfig("job.operation must be 'read' or 'write'");
        }
        if (job.mode != "sequential" && job.mode != "random") {
            failConfig("job.mode must be 'sequential' or 'random'");
        }
        if (job.run < 0) {
            failConfig("job.run must not be negative");
        }
        if (job.blockSizeBytes == 0) {
            failConfig("job.blockSizeBytes must be greater than zero");
        }
        if (job.queueDepth < 1 || job.queueDepth > 32) {
            failConfig("job.queueDepth must be between 1 and 32");
        }
        if (job.threads < 1 || job.threads > 16) {
            failConfig("job.threads must be between 1 and 16");
        }
        if (job.queueDepth * job.threads > 128) {
            failConfig("job.queueDepth * job.threads must not exceed 128");
        }
        if (job.durationSeconds <= 0) {
            failConfig("job.durationSeconds must be greater than zero");
        }
        if (job.intervalAfterMs < 0) {
            failConfig("job.intervalAfterMs must not be negative");
        }

        config.jobs.push_back(std::move(job));
    }

    return config;
}

}  // namespace diskmark
