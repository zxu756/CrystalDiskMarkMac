import AppKit
import Combine
import Darwin
import Foundation
import UniformTypeIdentifiers

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
    @Published public var settings: AppSettings
    @Published public private(set) var results: [String: BenchmarkResult] = [:]
    @Published public private(set) var runSettings: AppSettings?
    @Published public private(set) var runVolumeName: String?
    @Published public private(set) var state: BenchmarkState = .idle
    @Published public private(set) var statusText = ""
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var volumes: [VolumeInfo] = []
    @Published public var selectedVolume: VolumeInfo?
    @Published public var showSettings = false
    @Published public var showAbout = false
    @Published public private(set) var errorMessage: String?

    private let engineRunner: EngineRunning
    private let settingsStore: SettingsStore
    private let volumeCatalog: VolumeCatalog
    private var aggregator = ResultAggregator()
    private var stopped = false
    private var terminationObserver: NSObjectProtocol?

    public init(
        settings: AppSettings? = nil,
        engineRunner: EngineRunning? = nil,
        settingsStore: SettingsStore = SettingsStore(),
        volumeCatalog: VolumeCatalog = VolumeCatalog()
    ) {
        self.settingsStore = settingsStore
        self.settings = settings ?? settingsStore.load()
        self.engineRunner = engineRunner ?? EngineRunner(engineURL: EngineRunner.defaultEngineURL())
        self.volumeCatalog = volumeCatalog

        let initialVolumes = volumeCatalog.mountedVolumes()
        self.volumes = initialVolumes
        let bootVolume = initialVolumes.first(where: { $0.isBoot })

        if self.settings.targetPath.isEmpty, let bootVolume,
           let target = try? volumeCatalog.resolveTarget(for: bootVolume) {
            self.settings.targetPath = target.path
        } else if self.settings.targetPath == volumeCatalog.bootTargetPath {
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: self.settings.targetPath),
                withIntermediateDirectories: true
            )
        }

        if self.settings.targetPath == volumeCatalog.bootTargetPath {
            self.selectedVolume = bootVolume
        } else {
            self.selectedVolume = initialVolumes.first {
                !$0.isBoot &&
                (self.settings.targetPath == $0.url.path ||
                 self.settings.targetPath.hasPrefix($0.url.path + "/"))
            }
        }

        if !self.settings.targetPath.isEmpty {
            cleanupOrphanedSessions(at: URL(fileURLWithPath: self.settings.targetPath))
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopAndWait()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }

    public var isRunning: Bool {
        switch state {
        case .preparing, .running, .interval:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }

    public var displaySettings: AppSettings {
        runSettings ?? settings
    }

    public var targetDisplayName: String {
        if let selectedVolume {
            return selectedVolume.name
        }
        let url = URL(fileURLWithPath: settings.targetPath)
        return url.lastPathComponent.isEmpty ? "Select Folder" : url.lastPathComponent
    }

    public var targetFreeBytes: UInt64? {
        guard !settings.targetPath.isEmpty else { return nil }
        return try? volumeCatalog.freeBytes(at: URL(fileURLWithPath: settings.targetPath))
    }

    public func applyPreset(_ preset: AppSettings) {
        saveSettings(preset.preservingTargetPath(settings.targetPath))
    }

    public func runAll() {
        guard let target = validatedTarget() else { return }
        start(BenchmarkJobBuilder.allTests(settings: settings, target: target))
    }

    public func run(testIndex: Int) {
        guard let target = validatedTarget() else { return }
        start(BenchmarkJobBuilder.singleTest(settings: settings, testIndex: testIndex, target: target))
    }

    public func selectVolume(_ volume: VolumeInfo) {
        guard !isRunning else { return }
        do {
            let target = try volumeCatalog.resolveTarget(
                for: volume,
                requiredBytes: settings.testSizeBytes
            )
            settings.targetPath = target.path
            selectedVolume = volume
            saveSettings(settings)
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func selectFolder(_ url: URL) {
        guard !isRunning else { return }
        do {
            try volumeCatalog.validateFreeSpace(at: url, requiredBytes: settings.testSizeBytes)
            settings.targetPath = url.path
            selectedVolume = nil
            saveSettings(settings)
        } catch {
            fail(error.localizedDescription)
        }
    }

    public func chooseFolder() {
        guard let url = volumeCatalog.chooseFolder() else { return }
        selectFolder(url)
    }

    public func refreshVolumes() {
        volumes = volumeCatalog.mountedVolumes()
        if selectedVolume == nil {
            selectedVolume = volumes.first(where: { $0.isBoot }) ?? volumes.first
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        engineRunner.cancelAndWait(timeout: 3)
        aggregator.markStale()
        results = aggregator.results
        state = .idle
        statusText = "Stopped"
        progress = 0
    }

    public func stopAndWait() {
        guard !stopped else { return }
        stopped = true
        engineRunner.cancelAndWait(timeout: 3)
        aggregator.markStale()
        results = aggregator.results
        state = .idle
        statusText = "Stopped"
        progress = 0
    }

    public func saveSettings(_ newSettings: AppSettings) {
        guard !isRunning else { return }
        settings = newSettings
        settingsStore.save(newSettings)
    }

    public func persistSettings() {
        settingsStore.save(settings)
    }

    public func copyResults() {
        let text = resultsText()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func saveText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "CrystalDiskMarkMac.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? resultsText().write(to: url, atomically: true, encoding: .utf8)
    }

    public func saveImage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "CrystalDiskMarkMac.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = ResultImageRenderer.render(model: self),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        try? png.write(to: url)
    }

    private func resultsText() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        return ResultFormatter.textBlock(
            settings: runSettings ?? settings,
            results: results,
            date: Date(),
            osVersion: osVersion,
            volumeName: runVolumeName ?? targetDisplayName
        )
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
            statusText = message
            progress = 0
            aggregator.markStale()
            results = aggregator.results
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    func handleExit(code: Int32, stderr: String) {
        guard !stopped else { return }
        if case .failed = state {
            return
        }
        guard state != .finished else { return }

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
        runSettings = settings
        runVolumeName = targetDisplayName
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

    private func cleanupOrphanedSessions(at target: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: target,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for entry in entries where entry.lastPathComponent.hasPrefix("CrystalDiskMarkMac-") {
            let marker = entry.appendingPathComponent(".crystaldiskmark-mac-session")
            guard let text = try? String(contentsOf: marker, encoding: .utf8),
                  let pidLine = text.split(separator: "\n").first(where: { $0.hasPrefix("pid=") }),
                  let pid = pid_t(pidLine.dropFirst(4)) else {
                continue
            }

            if kill(pid, 0) != 0 {
                try? FileManager.default.removeItem(at: entry)
            }
        }
    }

    private func validatedTarget() -> URL? {
        guard !settings.targetPath.isEmpty else {
            fail("No target folder selected.")
            return nil
        }

        let url = URL(fileURLWithPath: settings.targetPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            fail("Target folder does not exist: \(url.path)")
            return nil
        }
        do {
            try volumeCatalog.validateFreeSpace(at: url, requiredBytes: settings.testSizeBytes)
            return url
        } catch {
            fail(error.localizedDescription)
            return nil
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        errorMessage = message
        statusText = message
        progress = 0
        aggregator.markStale()
        results = aggregator.results
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
