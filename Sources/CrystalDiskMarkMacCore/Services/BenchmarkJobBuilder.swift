import Foundation

public enum BenchmarkJobBuilder {
    public static func allTests(settings: AppSettings, target: URL) -> EngineConfig {
        let intervalMs = settings.intervalTime * 1_000
        var result: [BenchmarkJob] = []

        if settings.benchmarkMode != .writeOnly {
            for (index, test) in settings.tests.enumerated() {
                let isLastReadTest = index == settings.tests.count - 1
                let interval = isLastReadTest
                    ? (settings.benchmarkMode == .readWrite ? intervalMs : 0)
                    : intervalMs
                result.append(contentsOf: makeJobs(
                    for: test,
                    operation: .read,
                    settings: settings,
                    intervalAfterMs: interval
                ))
            }
        }

        if settings.benchmarkMode != .readOnly {
            for (index, test) in settings.tests.enumerated() {
                let isLastWriteTest = index == settings.tests.count - 1
                let interval = isLastWriteTest ? 0 : intervalMs
                result.append(contentsOf: makeJobs(
                    for: test,
                    operation: .write,
                    settings: settings,
                    intervalAfterMs: interval
                ))
            }
        }

        return EngineConfig(
            target: target.path,
            fileSizeBytes: settings.testSizeBytes,
            dataPattern: settings.dataPattern,
            jobs: result
        )
    }

    public static func singleTest(settings: AppSettings, testIndex: Int, target: URL) -> EngineConfig {
        guard settings.tests.indices.contains(testIndex) else {
            return EngineConfig(
                target: target.path,
                fileSizeBytes: settings.testSizeBytes,
                dataPattern: settings.dataPattern,
                jobs: []
            )
        }

        let test = settings.tests[testIndex]
        let intervalMs = settings.intervalTime * 1_000
        var result: [BenchmarkJob] = []

        if settings.benchmarkMode != .writeOnly {
            result.append(contentsOf: makeJobs(
                for: test,
                operation: .read,
                settings: settings,
                intervalAfterMs: settings.benchmarkMode == .readWrite ? intervalMs : 0
            ))
        }
        if settings.benchmarkMode != .readOnly {
            result.append(contentsOf: makeJobs(
                for: test,
                operation: .write,
                settings: settings,
                intervalAfterMs: 0
            ))
        }

        return EngineConfig(
            target: target.path,
            fileSizeBytes: settings.testSizeBytes,
            dataPattern: settings.dataPattern,
            jobs: result
        )
    }

    private static func makeJobs(
        for test: TestDefinition,
        operation: BenchmarkOperation,
        settings: AppSettings,
        intervalAfterMs: Int
    ) -> [BenchmarkJob] {
        (0...settings.testCount).map { run in
            BenchmarkJob(
                id: test.id,
                label: test.label,
                operation: operation,
                run: run,
                warmup: run == 0,
                mode: test.type,
                blockSizeBytes: test.blockSizeBytes,
                queueDepth: test.queues,
                threads: test.threads,
                durationSeconds: settings.measureTime,
                intervalAfterMs: run == settings.testCount ? intervalAfterMs : 0
            )
        }
    }
}
