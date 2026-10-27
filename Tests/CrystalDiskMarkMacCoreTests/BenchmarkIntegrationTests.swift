import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

@MainActor
struct BenchmarkIntegrationTests {
    final class ScriptedEngineRunner: EngineRunning {
        var configs: [EngineConfig] = []
        var onEvent: ((EngineEvent) -> Void)?
        var onExit: ((Int32, String) -> Void)?
        var cancelled = false

        func start(
            config: EngineConfig,
            onEvent: @escaping (EngineEvent) -> Void,
            onExit: @escaping (Int32, String) -> Void
        ) throws {
            configs.append(config)
            self.onEvent = onEvent
            self.onExit = onExit
        }

        func cancel() {
            cancelled = true
        }
    }

    private func makeHarness() throws -> (BenchmarkViewModel, ScriptedEngineRunner, URL, UserDefaults, String) {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdm-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        let suiteName = "BenchmarkIntegrationTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: suite)
        let runner = ScriptedEngineRunner()

        var settings = AppSettings.defaults
        settings.targetPath = target.path
        settings.measureTime = 1
        settings.intervalTime = 0

        let model = BenchmarkViewModel(settings: settings, engineRunner: runner, settingsStore: store)
        return (model, runner, target, suite, suiteName)
    }

    private func emitDefaultResults(_ runner: ScriptedEngineRunner) {
        let ids = ["seq-1m-q8t1", "seq-1m-q1t1", "rnd-4k-q32t1", "rnd-4k-q1t1"]
        for id in ids {
            runner.onEvent?(.result(testID: id, operation: .read, run: 1, warmup: false, mbps: 100, iops: 1_000, latencyUs: 10, cancelled: false))
            runner.onEvent?(.result(testID: id, operation: .write, run: 1, warmup: false, mbps: 80, iops: 800, latencyUs: 12, cancelled: false))
        }
    }

    @Test func runAllBuildsThirtyTwoJobsAndCollectsEightResults() throws {
        let (model, runner, target, suite, suiteName) = try makeHarness()
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: target)
        }

        model.runAll()
        #expect(model.state == .preparing)
        #expect(runner.configs.last?.jobs.count == 32)

        runner.onEvent?(.phase(phase: "create", message: "Creating"))
        emitDefaultResults(runner)
        runner.onEvent?(.done(ok: true))

        #expect(model.results.count == 8)
        #expect(model.state == .finished)
    }

    @Test func singleTestUpdatesOnlyItsRow() throws {
        let (model, runner, target, suite, suiteName) = try makeHarness()
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: target)
        }

        model.run(testIndex: 2)
        #expect(runner.configs.last?.jobs.count == 8)
        #expect(runner.configs.last?.jobs.first?.id == "rnd-4k-q32t1")

        runner.onEvent?(.result(testID: "rnd-4k-q32t1", operation: .read, run: 1, warmup: false, mbps: 450, iops: 109_000, latencyUs: 290, cancelled: false))
        runner.onEvent?(.done(ok: true))

        #expect(model.results.keys.sorted() == ["rnd-4k-q32t1-read"])
        #expect(model.results["rnd-4k-q32t1-read"]?.mbps == 450)
        #expect(model.state == .finished)
    }

    @Test func stopCancelsAndMarksResultsStale() throws {
        let (model, runner, target, suite, suiteName) = try makeHarness()
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: target)
        }

        model.runAll()
        runner.onEvent?(.result(testID: "seq-1m-q8t1", operation: .read, run: 1, warmup: false, mbps: 100, iops: 1_000, latencyUs: 10, cancelled: false))
        model.stop()

        #expect(runner.cancelled)
        #expect(model.state == .idle)
        let allStale = model.results.values.allSatisfy { $0.isStale }
        #expect(allStale)
    }

    @Test func exitWithoutDoneFailsAndKeepsResults() throws {
        let (model, runner, target, suite, suiteName) = try makeHarness()
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: target)
        }

        model.runAll()
        runner.onEvent?(.result(testID: "seq-1m-q8t1", operation: .read, run: 1, warmup: false, mbps: 100, iops: 1_000, latencyUs: 10, cancelled: false))
        model.handleExit(code: 1, stderr: "boom")

        #expect(model.state == .failed("Engine exited with code 1: boom"))
        #expect(model.results.count == 1)
    }

    @Test func malformedEventFailsWithoutCrashing() throws {
        let (model, runner, target, suite, suiteName) = try makeHarness()
        defer {
            suite.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: target)
        }

        model.runAll()
        runner.onEvent?(.error(code: "malformed_event", message: "not-json"))

        #expect(model.state == .failed("not-json"))
    }
}
