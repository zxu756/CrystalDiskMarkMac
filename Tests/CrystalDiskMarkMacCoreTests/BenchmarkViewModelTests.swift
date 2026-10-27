import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

@MainActor
struct BenchmarkViewModelTests {
    final class MockEngineRunner: EngineRunning {
        var configs: [EngineConfig] = []
        var onEvent: ((EngineEvent) -> Void)?
        var onExit: ((Int32, String) -> Void)?
        var cancelled = false
        var started = false

        func start(
            config: EngineConfig,
            onEvent: @escaping (EngineEvent) -> Void,
            onExit: @escaping (Int32, String) -> Void
        ) throws {
            configs.append(config)
            self.onEvent = onEvent
            self.onExit = onExit
            started = true
        }

        func cancel() {
            cancelled = true
        }
    }

    private func makeHarness() throws -> (BenchmarkViewModel, MockEngineRunner, UserDefaults, String) {
        let suiteName = "BenchmarkViewModelTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        let store = SettingsStore(defaults: suite)
        let runner = MockEngineRunner()
        let model = BenchmarkViewModel(
            settings: .defaults,
            engineRunner: runner,
            settingsStore: store
        )
        return (model, runner, suite, suiteName)
    }

    @Test func warmupIsIgnoredAndBestMeasuredResultWins() throws {
        let (model, _, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.handle(.result(testID: "seq", operation: .read, run: 0, warmup: true, mbps: 999, iops: 999, latencyUs: 1, cancelled: false))
        model.handle(.result(testID: "seq", operation: .read, run: 1, warmup: false, mbps: 100, iops: 10, latencyUs: 50, cancelled: false))
        model.handle(.result(testID: "seq", operation: .read, run: 2, warmup: false, mbps: 120, iops: 12, latencyUs: 40, cancelled: false))
        model.handle(.result(testID: "seq", operation: .read, run: 3, warmup: false, mbps: 110, iops: 11, latencyUs: 30, cancelled: false))

        let result = try #require(model.results["seq-read"])
        #expect(result.mbps == 120)
        #expect(result.iops == 12)
        #expect(result.latencyUs == 30)
    }

    @Test func stateTransitionsFollowEngineEvents() throws {
        let (model, _, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.handle(.phase(phase: "create", message: "Creating"))
        #expect(model.state == .preparing)

        model.handle(.run(testID: "seq", label: "SEQ1M Q8T1", operation: .read, run: 1, warmup: false, intervalAfterMs: 0))
        #expect(model.state == .running)

        model.handle(.interval(secondsRemaining: 3))
        #expect(model.state == .interval)

        model.handle(.done(ok: true))
        #expect(model.state == .finished)
    }

    @Test func errorEventSetsFailedState() throws {
        let (model, _, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.handle(.error(code: "io_failed", message: "boom"))
        #expect(model.state == .failed("boom"))
        #expect(model.errorMessage == "boom")
    }

    @Test func stopCancelsAndMarksResultsStale() throws {
        let (model, runner, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.handle(.result(testID: "seq", operation: .read, run: 1, warmup: false, mbps: 100, iops: 10, latencyUs: 50, cancelled: false))
        #expect(model.results["seq-read"]?.isStale == false)

        model.stop()

        #expect(runner.cancelled)
        #expect(model.state == .idle)
        let allResultsStale = model.results.values.allSatisfy { $0.isStale }
        #expect(allResultsStale)

        model.handle(.error(code: "cancelled", message: "Cancelled"))
        #expect(model.state == .idle)
    }

    @Test func runAllBuildsThirtyTwoJobs() throws {
        let (model, runner, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.runAll()

        #expect(runner.started)
        #expect(runner.configs.last?.jobs.count == 32)
        #expect(runner.configs.last?.target == model.settings.targetPath)
    }

    @Test func runSingleTestBuildsEightJobs() throws {
        let (model, runner, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.run(testIndex: 2)

        #expect(runner.started)
        #expect(runner.configs.last?.jobs.count == 8)
        #expect(runner.configs.last?.jobs.first?.id == "rnd-4k-q32t1-read")
    }

    @Test func exitWithoutDoneFails() throws {
        let (model, _, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        model.handleExit(code: 1, stderr: "boom")
        #expect(model.state == .failed("Engine exited with code 1: boom"))
    }

    @Test func saveSettingsPersists() throws {
        let (model, _, suite, suiteName) = try makeHarness()
        defer { suite.removePersistentDomain(forName: suiteName) }

        var settings = model.settings
        settings.testCount = 7
        model.saveSettings(settings)

        #expect(model.settings.testCount == 7)
        #expect(SettingsStore(defaults: suite).load().testCount == 7)
    }

    @Test func previewHasSampleResults() {
        #expect(!BenchmarkViewModel.preview.results.isEmpty)
    }
}
