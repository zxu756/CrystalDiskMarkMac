import Foundation

public struct BenchmarkResult: Equatable, Identifiable, Sendable {
    public let testID: String
    public let operation: BenchmarkOperation
    public var mbps: Double
    public var iops: Double
    public var latencyUs: Double
    public var isStale: Bool

    public var id: String { "\(testID)-\(operation.rawValue)" }

    public init(
        testID: String,
        operation: BenchmarkOperation,
        mbps: Double,
        iops: Double,
        latencyUs: Double,
        isStale: Bool = false
    ) {
        self.testID = testID
        self.operation = operation
        self.mbps = mbps
        self.iops = iops
        self.latencyUs = latencyUs
        self.isStale = isStale
    }
}
