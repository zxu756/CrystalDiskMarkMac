import Foundation

public enum BenchmarkType: String, Codable, CaseIterable, Hashable, Sendable {
    case sequential
    case random
}

public enum BenchmarkOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case read
    case write
}

public enum BenchmarkUnit: Int, Codable, CaseIterable, Hashable, Sendable {
    case mbps = 0
    case gbps = 1
    case iops = 2
    case microseconds = 3

    public var label: String {
        switch self {
        case .mbps: return "MB/s"
        case .gbps: return "GB/s"
        case .iops: return "IOPS"
        case .microseconds: return "µs"
        }
    }
}

public enum DataPattern: String, Codable, CaseIterable, Hashable, Sendable {
    case random
    case zero
}

public enum BenchmarkMode: String, Codable, CaseIterable, Hashable, Sendable {
    case readWrite
    case readOnly
    case writeOnly
}

public enum BenchmarkProfile: String, Codable, CaseIterable, Hashable, Sendable {
    case defaultProfile = "default"
    case peak
    case realWorld
    case demo

    public var displayName: String {
        switch self {
        case .defaultProfile: return "Default"
        case .peak: return "Peak"
        case .realWorld: return "Real World"
        case .demo: return "Demo"
        }
    }
}

public struct TestDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: BenchmarkType
    public var blockSizeBytes: UInt64
    public var queues: Int
    public var threads: Int

    public init(id: String, type: BenchmarkType, blockSizeBytes: UInt64, queues: Int, threads: Int) {
        self.id = id
        self.type = type
        self.blockSizeBytes = blockSizeBytes
        self.queues = queues
        self.threads = threads
    }

    public var label: String {
        let prefix = type == .sequential ? "SEQ" : "RND"
        let size: String

        if blockSizeBytes >= 1_048_576 && blockSizeBytes % 1_048_576 == 0 {
            size = "\(blockSizeBytes / 1_048_576)M"
        } else if blockSizeBytes >= 1_024 && blockSizeBytes % 1_024 == 0 {
            size = "\(blockSizeBytes / 1_024)K"
        } else {
            size = "\(blockSizeBytes)B"
        }

        return "\(prefix)\(size) Q\(queues)T\(threads)"
    }
}
