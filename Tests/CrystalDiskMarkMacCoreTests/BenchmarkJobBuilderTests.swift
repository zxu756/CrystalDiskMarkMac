import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

struct BenchmarkJobBuilderTests {
    let target = URL(fileURLWithPath: "/tmp/cdm-test")

    @Test func defaultAllTestsHas32JobsAndCDMOrder() {
        let config = BenchmarkJobBuilder.allTests(settings: .defaults, target: target)

        #expect(config.jobs.count == 32)
        #expect(config.jobs.prefix(16).map(\.operation) == Array(repeating: .read, count: 16))
        #expect(config.jobs.suffix(16).map(\.operation) == Array(repeating: .write, count: 16))
        #expect(config.jobs.first?.id == "seq-1m-q8t1")
        #expect(config.jobs.last?.id == "rnd-4k-q1t1")
    }

    @Test func intervalsOnlyAfterLastMeasuredRun() {
        let config = BenchmarkJobBuilder.allTests(settings: .defaults, target: target)
        let intervalJobs = config.jobs.filter { $0.intervalAfterMs > 0 }

        #expect(intervalJobs.count == 7)
        #expect(intervalJobs.allSatisfy { !$0.warmup && $0.run == 3 && $0.intervalAfterMs == 5_000 })
    }

    @Test func readOnlyHasThreeIntervals() {
        var settings = AppSettings.defaults
        settings.benchmarkMode = .readOnly

        let config = BenchmarkJobBuilder.allTests(settings: settings, target: target)

        #expect(config.jobs.count == 16)
        #expect(config.jobs.allSatisfy { $0.operation == .read })
        #expect(config.jobs.filter { $0.intervalAfterMs > 0 }.count == 3)
    }

    @Test func writeOnlyHasThreeIntervals() {
        var settings = AppSettings.defaults
        settings.benchmarkMode = .writeOnly

        let config = BenchmarkJobBuilder.allTests(settings: settings, target: target)

        #expect(config.jobs.count == 16)
        #expect(config.jobs.allSatisfy { $0.operation == .write })
        #expect(config.jobs.filter { $0.intervalAfterMs > 0 }.count == 3)
    }

    @Test func singleTestRunsReadThenWrite() {
        let config = BenchmarkJobBuilder.singleTest(settings: .defaults, testIndex: 0, target: target)

        #expect(config.jobs.count == 8)
        #expect(config.jobs.prefix(4).map(\.operation) == Array(repeating: .read, count: 4))
        #expect(config.jobs.suffix(4).map(\.operation) == Array(repeating: .write, count: 4))
        #expect(config.jobs.filter { $0.intervalAfterMs > 0 }.count == 1)
    }

    @Test func jobValuesMatchDefaults() {
        let config = BenchmarkJobBuilder.allTests(settings: .defaults, target: target)
        let first = config.jobs[0]
        let lastReadRun = config.jobs[3]

        #expect(config.target == target.path)
        #expect(config.fileSizeBytes == 1_073_741_824)
        #expect(config.dataPattern == .random)
        #expect(first.id == "seq-1m-q8t1")
        #expect(first.label == "SEQ1M Q8T1")
        #expect(first.operation == .read)
        #expect(first.run == 0)
        #expect(first.warmup)
        #expect(first.mode == .sequential)
        #expect(first.blockSizeBytes == 1_048_576)
        #expect(first.queueDepth == 8)
        #expect(first.threads == 1)
        #expect(first.durationSeconds == 5)
        #expect(first.intervalAfterMs == 0)
        #expect(lastReadRun.run == 3)
        #expect(lastReadRun.intervalAfterMs == 5_000)
    }
}
