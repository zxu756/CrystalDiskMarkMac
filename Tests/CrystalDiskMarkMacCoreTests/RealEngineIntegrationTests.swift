import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

private final class RealEngineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [EngineEvent] = []
    private var code: Int32?

    func add(_ event: EngineEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func finish(code: Int32) {
        lock.lock()
        self.code = code
        lock.unlock()
    }

    var events: [EngineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var exitCode: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return code
    }
}

@MainActor
struct RealEngineIntegrationTests {
    private func engineURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent(".build/out/Products/Debug/DiskMarkEngine"),
            root.appendingPathComponent(".build/debug/DiskMarkEngine"),
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/DiskMarkEngine")
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw EngineRunnerError.engineMissing(candidates[0])
    }

    @Test func realEngineRunsThroughSwiftRunner() async throws {
        let engine = try engineURL()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdm-real-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: target) }

        let job = BenchmarkJob(
            id: "real",
            label: "Real",
            operation: .read,
            run: 1,
            warmup: false,
            mode: .sequential,
            blockSizeBytes: 1_048_576,
            queueDepth: 1,
            threads: 1,
            durationSeconds: 1,
            intervalAfterMs: 0
        )
        let config = EngineConfig(
            target: target.path,
            fileSizeBytes: 16 * 1024 * 1024,
            dataPattern: .random,
            jobs: [job]
        )

        let collector = RealEngineCollector()
        let runner = EngineRunner(engineURL: engine, callbackQueue: .main)
        try runner.start(
            config: config,
            onEvent: { collector.add($0) },
            onExit: { code, _ in collector.finish(code: code) }
        )

        for _ in 0..<100 {
            if collector.exitCode != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        #expect(collector.exitCode == 0)
        #expect(collector.events.contains { event in
            if case .result = event { return true }
            return false
        })

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: target.path)
        #expect(!leftovers.contains { $0.hasPrefix("CrystalDiskMarkMac-") })
    }
}
