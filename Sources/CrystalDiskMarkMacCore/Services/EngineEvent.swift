import Foundation

public enum EngineEvent: Equatable, Sendable {
    case phase(phase: String, message: String)
    case run(
        testID: String,
        label: String,
        operation: BenchmarkOperation,
        run: Int,
        warmup: Bool,
        intervalAfterMs: Int
    )
    case progress(testID: String, operation: BenchmarkOperation, elapsedMs: Int, bytes: UInt64)
    case interval(secondsRemaining: Int)
    case result(
        testID: String,
        operation: BenchmarkOperation,
        run: Int,
        warmup: Bool,
        mbps: Double,
        iops: Double,
        latencyUs: Double,
        cancelled: Bool
    )
    case done(ok: Bool)
    case error(code: String, message: String)
}

public enum EngineEventError: Error, Equatable, CustomStringConvertible {
    case invalidJSON
    case malformed(String)

    public var description: String {
        switch self {
        case .invalidJSON:
            return "invalid JSON event"
        case .malformed(let message):
            return message
        }
    }
}

public enum EngineEventDecoder {
    public static func decode(_ line: String) throws -> EngineEvent {
        guard let data = line.data(using: .utf8) else {
            throw EngineEventError.malformed("event is not valid UTF-8")
        }

        let object: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EngineEventError.malformed("event is not an object")
            }
            object = parsed
        } catch let error as EngineEventError {
            throw error
        } catch {
            throw EngineEventError.invalidJSON
        }

        guard let name = object["event"] as? String else {
            throw EngineEventError.malformed("missing event name")
        }

        switch name {
        case "phase":
            return .phase(
                phase: try string(object, "phase"),
                message: try string(object, "message")
            )
        case "run":
            return .run(
                testID: try string(object, "test"),
                label: try string(object, "label"),
                operation: try operation(object),
                run: try int(object, "run"),
                warmup: try bool(object, "warmup"),
                intervalAfterMs: try int(object, "intervalAfterMs")
            )
        case "progress":
            return .progress(
                testID: try string(object, "test"),
                operation: try operation(object),
                elapsedMs: try int(object, "elapsedMs"),
                bytes: try uint64(object, "bytes")
            )
        case "interval":
            return .interval(secondsRemaining: try int(object, "secondsRemaining"))
        case "result":
            return .result(
                testID: try string(object, "test"),
                operation: try operation(object),
                run: try int(object, "run"),
                warmup: try bool(object, "warmup"),
                mbps: try double(object, "mbps"),
                iops: try double(object, "iops"),
                latencyUs: try double(object, "latencyUs"),
                cancelled: try bool(object, "cancelled")
            )
        case "done":
            return .done(ok: try bool(object, "ok"))
        case "error":
            return .error(
                code: try string(object, "code"),
                message: try string(object, "message")
            )
        default:
            throw EngineEventError.malformed("unknown event: \(name)")
        }
    }

    private static func string(_ object: [String: Any], _ key: String) throws -> String {
        guard let value = object[key] as? String else {
            throw EngineEventError.malformed("missing string field: \(key)")
        }
        return value
    }

    private static func int(_ object: [String: Any], _ key: String) throws -> Int {
        guard let value = object[key] as? NSNumber else {
            throw EngineEventError.malformed("missing integer field: \(key)")
        }
        return value.intValue
    }

    private static func uint64(_ object: [String: Any], _ key: String) throws -> UInt64 {
        guard let value = object[key] as? NSNumber else {
            throw EngineEventError.malformed("missing integer field: \(key)")
        }
        return value.uint64Value
    }

    private static func double(_ object: [String: Any], _ key: String) throws -> Double {
        guard let value = object[key] as? NSNumber else {
            throw EngineEventError.malformed("missing number field: \(key)")
        }
        return value.doubleValue
    }

    private static func bool(_ object: [String: Any], _ key: String) throws -> Bool {
        guard let value = object[key] as? NSNumber else {
            throw EngineEventError.malformed("missing boolean field: \(key)")
        }
        return value.boolValue
    }

    private static func operation(_ object: [String: Any]) throws -> BenchmarkOperation {
        let raw = try string(object, "operation")
        guard let operation = BenchmarkOperation(rawValue: raw) else {
            throw EngineEventError.malformed("unknown operation: \(raw)")
        }
        return operation
    }
}

public struct LineBuffer {
    private var storage = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        storage.append(data)
        var lines: [String] = []

        while let newline = storage.firstIndex(of: 0x0A) {
            var lineData = storage[..<newline]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            lines.append(String(decoding: lineData, as: UTF8.self))
            storage.removeSubrange(storage.startIndex...newline)
        }

        return lines
    }
}
