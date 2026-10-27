import AppKit
import Combine
import Foundation

public enum BenchmarkState: Equatable, Sendable {
    case idle
    case preparing
    case running
    case interval
    case finished
    case failed(String)
}

@MainActor
public final class BenchmarkViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var results: [String: BenchmarkResult] = [:]
    @Published public private(set) var state: BenchmarkState = .idle
    @Published public private(set) var statusText = ""
    @Published public private(set) var progress: Double = 0
    @Published public var selectedVolume: VolumeInfo?
    @Published public var showSettings = false
    @Published public var showAbout = false
    @Published public private(set) var errorMessage: String?

    private let engineRunner: EngineRunning
    private let settingsStore: SettingsStore
    private var aggregator = ResultAggregator()
    private var stopped = false
    private var terminationObserver: NSObjectProtocol?

    public init(
        settings: AppSettings? = nil,
        engineRunner: EngineRunning? = nil,
        settingsStore: SettingsStore = SettingsStore()
    ) {
        self.settingsStore = settingsStore
        self.settings = settings ?? settingsStore.load()
        self.engineRunner = engineRunner ?? EngineRunner(engineURL: EngineRunner.defaultEngineURL())

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stop()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    public func runAll() {
        guard let target = targetURL() else {
            fail("No target folder selected.")
            return
        }
        start(BenchmarkJobBuilder.allTests(settings: settings, target: target))
    }

    public func run(testIndex: Int) {
        guard let target = targetURL() else {
            fail("No target folder selected.")
            return
        }
        start(BenchmarkJobBuilder.singleTest(settings: settings, testIndex: testIndex, target: target))
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        engineRunner.cancel()
        aggregator.markStale()
        results = aggregator.results
        state = .idle
        statusText = "Stopped"
        progress = 0
    }

    public func saveSettings(_ newSettings: AppSettings) {
        settings = newSettings
        settingsStore.save(newSettings)
    }

    func handle(_ event: EngineEvent) {
        guard !stopped else { return }

        switch event {
        case .phase(_, let message):
            state = .preparing
            statusText = message
        case .run(_, let label, let operation, let run, let warmup, _):
            state = .running
            if warmup {
                statusText = "\(label) \(operation.rawValue.capitalized) warm-up"
            } else {
                statusText = "\(label) \(operation.rawValue.capitalized) \(run)/\(settings.testCount)"
            }
            progress = 0
        case .progress(_, _, let elapsedMs, _):
            let durationMs = max(settings.measureTime * 1_000, 1)
            progress = min(Double(elapsedMs) / Double(durationMs), 1.0)
        case .interval(let secondsRemaining):
            state = .interval
            statusText = "Interval Time \(secondsRemaining)/\(settings.intervalTime) sec"
            progress = 0
        case .result:
            aggregator.ingest(event)
            results = aggregator.results
        case .done:
            state = .finished
            statusText = "Done"
            progress = 1
        case .error(_, let message):
            state = .failed(message)
            errorMessage = message
            statusText = "Failed"
            progress = 0
        }
    }

    func handleExit(code: Int32, stderr: String) {
        guard !stopped, state != .finished else { return }
        if code == 0 {
            fail("Engine exited without completion.")
        } else if stderr.isEmpty {
            fail("Engine exited with code \(code).")
        } else {
            fail("Engine exited with code \(code): \(stderr)")
        }
    }

    private func start(_ config: EngineConfig) {
        switch state {
        case .preparing, .running, .interval:
            return
        case .idle, .finished, .failed:
            break
        }

        state = .preparing
        statusText = "Preparing..."
        progress = 0
        errorMessage = nil
        stopped = false
        aggregator = ResultAggregator()
        results = [:]

        do {
            try engineRunner.start(
                config: config,
                onEvent: { [weak self] event in
                    self?.handle(event)
                },
                onExit: { [weak self] code, stderr in
                    self?.handleExit(code: code, stderr: stderr)
                }
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func targetURL() -> URL? {
        guard !settings.targetPath.isEmpty else { return nil }
        return URL(fileURLWithPath: settings.targetPath)
    }

    private func fail(_ message: String) {
        state = .failed(message)
        errorMessage = message
        statusText = "Failed"
        progress = 0
    }

    public static var preview: BenchmarkViewModel {
        let model = BenchmarkViewModel(settings: .defaults, engineRunner: PreviewEngineRunner())
        model.results = [
            "seq-1m-q8t1-read": BenchmarkResult(testID: "seq-1m-q8t1", operation: .read, mbps: 3120.4, iops: 2977.1, latencyUs: 42.7),
            "seq-1m-q8t1-write": BenchmarkResult(testID: "seq-1m-q8t1", operation: .write, mbps: 2804.8, iops: 2675.9, latencyUs: 51.2),
            "seq-1m-q1t1-read": BenchmarkResult(testID: "seq-1m-q1t1", operation: .read, mbps: 2410.2, iops: 2299.4, latencyUs: 88.1),
            "seq-1m-q1t1-write": BenchmarkResult(testID: "seq-1m-q1t1", operation: .write, mbps: 2204.6, iops: 2103.1, latencyUs: 96.4),
            "rnd-4k-q32t1-read": BenchmarkResult(testID: "rnd-4k-q32t1", operation: .read, mbps: 450.3, iops: 109936.5, latencyUs: 291.2),
            "rnd-4k-q32t1-write": BenchmarkResult(testID: "rnd-4k-q32t1", operation: .write, mbps: 380.7, iops: 92944.3, latencyUs: 344.8),
            "rnd-4k-q1t1-read": BenchmarkResult(testID: "rnd-4k-q1t1", operation: .read, mbps: 52.4, iops: 12792.9, latencyUs: 78.1),
            "rnd-4k-q1t1-write": BenchmarkResult(testID: "rnd-4k-q1t1", operation: .write, mbps: 48.1, iops: 11743.2, latencyUs: 85.4)
        ]
        return model
    }
}

private final class PreviewEngineRunner: EngineRunning {
    func start(
        config: EngineConfig,
        onEvent: @escaping (EngineEvent) -> Void,
        onExit: @escaping (Int32, String) -> Void
    ) throws {}
    func cancel() {}
}
