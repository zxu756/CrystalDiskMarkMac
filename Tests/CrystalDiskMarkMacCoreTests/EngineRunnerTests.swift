import Testing
import Foundation
import Dispatch
@testable import CrystalDiskMarkMacCore

private final class EventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [EngineEvent] = []
    private var code: Int32?
    private var errorText = ""

    func add(_ event: EngineEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func finish(code: Int32, stderr: String) {
        lock.lock()
        self.code = code
        self.errorText = stderr
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

    var stderr: String {
        lock.lock()
        defer { lock.unlock() }
        return errorText
    }
}

struct EngineRunnerTests {
    private func makeScript(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdm-engine-runner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("fake-engine.sh")
        try "#!/bin/sh\n\(body)\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )
        return script
    }

    private func config() -> EngineConfig {
        EngineConfig(
            target: "/tmp/cdm-test",
            fileSizeBytes: 16 * 1024 * 1024,
            dataPattern: .random,
            jobs: [
                BenchmarkJob(
                    id: "test",
                    label: "Test",
                    operation: .read,
                    run: 0,
                    warmup: true,
                    mode: .sequential,
                    blockSizeBytes: 1_048_576,
                    queueDepth: 1,
                    threads: 1,
                    durationSeconds: 1,
                    intervalAfterMs: 0
                )
            ]
        )
    }

    @Test func runsFakeEngineAndCollectsEvents() throws {
        let script = try makeScript(#"printf '%s\n' '{"event":"phase","phase":"create","message":"Creating"}' '{"event":"done","ok":true}'"#)
        let collector = EventCollector()
        let exited = DispatchSemaphore(value: 0)
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-events"))

        try runner.start(
            config: config(),
            onEvent: { collector.add($0) },
            onExit: { code, stderr in
                collector.finish(code: code, stderr: stderr)
                exited.signal()
            }
        )

        #expect(exited.wait(timeout: .now() + 5) == .success)
        #expect(collector.exitCode == 0)
        #expect(collector.events.count == 2)
        #expect(collector.events.first == .phase(phase: "create", message: "Creating"))
        #expect(collector.events.last == .done(ok: true))
    }

    @Test func malformedLineEmitsErrorAndStops() throws {
        let script = try makeScript(#"printf '%s\n' 'not-json'"#)
        let collector = EventCollector()
        let exited = DispatchSemaphore(value: 0)
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-malformed"))

        try runner.start(
            config: config(),
            onEvent: { collector.add($0) },
            onExit: { code, stderr in
                collector.finish(code: code, stderr: stderr)
                exited.signal()
            }
        )

        #expect(exited.wait(timeout: .now() + 5) == .success)
        #expect(collector.events.contains { event in
            if case .error(let code, _) = event { return code == "malformed_event" }
            return false
        })
    }

    @Test func stderrTailIsDelivered() throws {
        let script = try makeScript(#"printf '%s\n' '{"event":"done","ok":true}'; echo boom >&2; exit 1"#)
        let collector = EventCollector()
        let exited = DispatchSemaphore(value: 0)
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-stderr"))

        try runner.start(
            config: config(),
            onEvent: { collector.add($0) },
            onExit: { code, stderr in
                collector.finish(code: code, stderr: stderr)
                exited.signal()
            }
        )

        #expect(exited.wait(timeout: .now() + 5) == .success)
        #expect(collector.exitCode == 1)
        #expect(collector.stderr.contains("boom"))
    }

    @Test func missingEngineThrows() {
        let runner = EngineRunner(engineURL: URL(fileURLWithPath: "/tmp/does-not-exist-cdm-engine"))
        #expect(throws: EngineRunnerError.self) {
            try runner.start(config: config(), onEvent: { _ in }, onExit: { _, _ in })
        }
    }

    @Test func startWhileRunningThrows() throws {
        let script = try makeScript("sleep 5")
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-single-flight"))
        try runner.start(config: config(), onEvent: { _ in }, onExit: { _, _ in })

        #expect(throws: EngineRunnerError.self) {
            try runner.start(config: config(), onEvent: { _ in }, onExit: { _, _ in })
        }

        runner.cancelAndWait(timeout: 3)
    }

    @Test func cancelAndWaitAllowsRestart() throws {
        let script = try makeScript("sleep 2")
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-restart"))
        try runner.start(config: config(), onEvent: { _ in }, onExit: { _, _ in })
        runner.cancelAndWait(timeout: 3)

        try runner.start(config: config(), onEvent: { _ in }, onExit: { _, _ in })
        runner.cancelAndWait(timeout: 3)
    }

    @Test func cancelStopsSleepingEngine() throws {
        let script = try makeScript("sleep 10")
        let collector = EventCollector()
        let exited = DispatchSemaphore(value: 0)
        let runner = EngineRunner(engineURL: script, callbackQueue: DispatchQueue(label: "cdm-test-cancel"))

        try runner.start(
            config: config(),
            onEvent: { collector.add($0) },
            onExit: { code, stderr in
                collector.finish(code: code, stderr: stderr)
                exited.signal()
            }
        )

        Thread.sleep(forTimeInterval: 0.2)
        runner.cancel()

        #expect(exited.wait(timeout: .now() + 5) == .success)
        #expect(collector.exitCode != nil)
    }
}
