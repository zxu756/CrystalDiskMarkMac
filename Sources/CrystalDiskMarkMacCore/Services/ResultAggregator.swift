import Foundation

public struct ResultAggregator {
    public private(set) var results: [String: BenchmarkResult] = [:]

    public init() {}

    public mutating func ingest(_ event: EngineEvent) {
        guard case let .result(testID, operation, _, warmup, mbps, iops, latencyUs, _) = event,
              !warmup else {
            return
        }

        let key = "\(testID)-\(operation.rawValue)"
        if var existing = results[key] {
            existing.mbps = max(existing.mbps, mbps)
            existing.iops = max(existing.iops, iops)
            existing.latencyUs = min(existing.latencyUs, latencyUs)
            existing.isStale = false
            results[key] = existing
        } else {
            results[key] = BenchmarkResult(
                testID: testID,
                operation: operation,
                mbps: mbps,
                iops: iops,
                latencyUs: latencyUs
            )
        }
    }

    public mutating func markStale() {
        for key in Array(results.keys) {
            results[key]?.isStale = true
        }
    }
}
