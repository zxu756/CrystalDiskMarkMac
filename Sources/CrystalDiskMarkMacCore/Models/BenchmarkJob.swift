import Foundation

public struct BenchmarkJob: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let operation: BenchmarkOperation
    public let run: Int
    public let warmup: Bool
    public let mode: BenchmarkType
    public let blockSizeBytes: UInt64
    public let queueDepth: Int
    public let threads: Int
    public let durationSeconds: Int
    public let intervalAfterMs: Int

    public init(
        id: String,
        label: String,
        operation: BenchmarkOperation,
        run: Int,
        warmup: Bool,
        mode: BenchmarkType,
        blockSizeBytes: UInt64,
        queueDepth: Int,
        threads: Int,
        durationSeconds: Int,
        intervalAfterMs: Int
    ) {
        self.id = id
        self.label = label
        self.operation = operation
        self.run = run
        self.warmup = warmup
        self.mode = mode
        self.blockSizeBytes = blockSizeBytes
        self.queueDepth = queueDepth
        self.threads = threads
        self.durationSeconds = durationSeconds
        self.intervalAfterMs = intervalAfterMs
    }
}

public struct EngineConfig: Codable, Equatable, Sendable {
    public let target: String
    public let fileSizeBytes: UInt64
    public let dataPattern: DataPattern
    public let jobs: [BenchmarkJob]

    public init(target: String, fileSizeBytes: UInt64, dataPattern: DataPattern, jobs: [BenchmarkJob]) {
        self.target = target
        self.fileSizeBytes = fileSizeBytes
        self.dataPattern = dataPattern
        self.jobs = jobs
    }
}
