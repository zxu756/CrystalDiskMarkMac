import Foundation
import Darwin

public enum EngineRunnerError: LocalizedError, Equatable {
    case engineMissing(URL)
    case configWriteFailed(String)
    case alreadyRunning

    public var errorDescription: String? {
        switch self {
        case .engineMissing(let url):
            return "DiskMarkEngine not found or not executable: \(url.path)"
        case .configWriteFailed(let message):
            return "Could not write engine config: \(message)"
        case .alreadyRunning:
            return "A benchmark is already running."
        }
    }
}

public protocol EngineRunning: AnyObject {
    func start(
        config: EngineConfig,
        onEvent: @escaping (EngineEvent) -> Void,
        onExit: @escaping (Int32, String) -> Void
    ) throws
    func cancel()
    func cancelAndWait(timeout: TimeInterval)
}

public extension EngineRunning {
    func cancelAndWait(timeout: TimeInterval) {
        cancel()
    }
}

public final class EngineRunner: EngineRunning {
    private let engineURL: URL
    private let callbackQueue: DispatchQueue
    private let workQueue = DispatchQueue(label: "CrystalDiskMarkMac.EngineRunner")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var configURL: URL?
    private var lineBuffer = LineBuffer()
    private var stderrTail = Data()
    private var onEvent: ((EngineEvent) -> Void)?
    private var onExit: ((Int32, String) -> Void)?
    private var finished = false
    private var generation: UInt64 = 0

    public init(engineURL: URL, callbackQueue: DispatchQueue = .main) {
        self.engineURL = engineURL
        self.callbackQueue = callbackQueue
    }

    public static func defaultEngineURL() -> URL {
        if let path = ProcessInfo.processInfo.environment["DISKMARK_ENGINE_PATH"] {
            return URL(fileURLWithPath: path)
        }
        if let url = Bundle.main.url(forAuxiliaryExecutable: "DiskMarkEngine") {
            return url
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/DiskMarkEngine")
    }

    public func start(
        config: EngineConfig,
        onEvent: @escaping (EngineEvent) -> Void,
        onExit: @escaping (Int32, String) -> Void
    ) throws {
        guard process?.isRunning != true else {
            throw EngineRunnerError.alreadyRunning
        }

        guard FileManager.default.isExecutableFile(atPath: engineURL.path) else {
            throw EngineRunnerError.engineMissing(engineURL)
        }

        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskMarkEngine-\(UUID().uuidString).json")
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            throw EngineRunnerError.configWriteFailed(error.localizedDescription)
        }

        self.configURL = configURL
        self.onEvent = onEvent
        self.onExit = onExit
        self.lineBuffer = LineBuffer()
        self.stderrTail = Data()
        self.finished = false
        generation &+= 1
        let runGeneration = generation

        let process = Process()
        process.executableURL = engineURL
        process.arguments = ["--config", configURL.path]
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.workQueue.async {
                guard let self, self.generation == runGeneration else { return }
                self.consumeStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.workQueue.async {
                guard let self, self.generation == runGeneration else { return }
                self.consumeStderr(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            self?.workQueue.async {
                self?.finish(exitCode: process.terminationStatus, generation: runGeneration)
            }
        }

        do {
            try process.run()
        } catch {
            cleanup()
            throw EngineRunnerError.engineMissing(engineURL)
        }
    }

    public func cancel() {
        workQueue.async { [weak self] in
            guard let self, let process = self.process, process.isRunning else { return }
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
    }

    public func cancelAndWait(timeout: TimeInterval) {
        var process: Process?
        workQueue.sync {
            process = self.process
            if process?.isRunning == true {
                process?.terminate()
            }
        }

        guard let process, process.isRunning else { return }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            exited.signal()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }

        workQueue.sync {
            self.generation &+= 1
            self.finished = true
            self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            self.stderrPipe?.fileHandleForReading.readabilityHandler = nil
            self.process = nil
            self.stdoutPipe = nil
            self.stderrPipe = nil
            self.onEvent = nil
            self.onExit = nil
            self.cleanup()
        }
    }

    private func consumeStdout(_ data: Data) {
        for line in lineBuffer.append(data) where !line.isEmpty {
            do {
                emit(try EngineEventDecoder.decode(line))
            } catch {
                emit(.error(code: "malformed_event", message: line))
                process?.terminate()
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > 65_536 {
            stderrTail = stderrTail.suffix(65_536)
        }
    }

    private func emit(_ event: EngineEvent) {
        guard let onEvent else { return }
        callbackQueue.async { onEvent(event) }
    }

    private func finish(exitCode: Int32, generation: UInt64) {
        guard !finished, self.generation == generation else { return }
        finished = true

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let pipe = stdoutPipe {
            consumeStdout(pipe.fileHandleForReading.readDataToEndOfFile())
        }
        if let pipe = stderrPipe {
            consumeStderr(pipe.fileHandleForReading.readDataToEndOfFile())
        }

        let tail = String(decoding: stderrTail, as: UTF8.self)
        let callback = onExit
        callbackQueue.async { callback?(exitCode, tail) }

        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        onEvent = nil
        onExit = nil
        cleanup()
    }

    private func cleanup() {
        if let configURL {
            try? FileManager.default.removeItem(at: configURL)
        }
        configURL = nil
    }
}
