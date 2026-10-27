import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

struct AppSettingsTests {
    @Test func defaultsMatchCrystalDiskMark() {
        let settings = AppSettings.defaults

        #expect(settings.testCount == 3)
        #expect(settings.testSizeIndex == 6)
        #expect(settings.unit == .mbps)
        #expect(settings.profile == .defaultProfile)
        #expect(settings.measureTime == 5)
        #expect(settings.intervalTime == 5)
        #expect(settings.dataPattern == .random)
        #expect(settings.benchmarkMode == .readWrite)
        #expect(settings.tests.map(\.label) == ["SEQ1M Q8T1", "SEQ1M Q1T1", "RND4K Q32T1", "RND4K Q1T1"])
        #expect(settings.tests.map(\.id) == ["seq-1m-q8t1", "seq-1m-q1t1", "rnd-4k-q32t1", "rnd-4k-q1t1"])
        #expect(settings.tests.map(\.blockSizeBytes) == [1_048_576, 1_048_576, 4_096, 4_096])
        #expect(settings.tests.map(\.queues) == [8, 1, 32, 1])
        #expect(settings.tests.map(\.threads) == [1, 1, 1, 1])
    }

    @Test func testSizeMapping() {
        #expect(AppSettings.defaults.testSizeBytes == 1_073_741_824)

        var settings = AppSettings.defaults
        settings.testSizeIndex = 0
        #expect(settings.testSizeBytes == 16_777_216)
        #expect(settings.testSizeLabel == "16 MiB")

        settings.testSizeIndex = 12
        #expect(settings.testSizeBytes == 68_719_476_736)
        #expect(settings.testSizeLabel == "64 GiB")
    }

    @Test func validationRejectsConcurrencyAbove128() {
        var settings = AppSettings.defaults
        settings.tests[0].queues = 32
        settings.tests[0].threads = 5
        #expect(settings.validate().contains { $0.field == "threads" })

        settings.tests[0].threads = 4
        #expect(!settings.validate().contains { $0.field == "threads" })
    }

    @Test func validationRejectsOutOfRangeValues() {
        var settings = AppSettings.defaults
        settings.testCount = 0
        settings.testSizeIndex = 13
        settings.measureTime = 11
        settings.intervalTime = 2
        settings.tests[0].blockSizeBytes = 123
        settings.tests[0].queues = 0

        let fields = Set(settings.validate().map(\.field))
        #expect(fields.contains("testCount"))
        #expect(fields.contains("testSizeIndex"))
        #expect(fields.contains("measureTime"))
        #expect(fields.contains("intervalTime"))
        #expect(fields.contains("blockSizeBytes"))
        #expect(fields.contains("queues"))
    }

    @Test func settingsRoundTrip() throws {
        let suiteName = "AppSettingsTests.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: suite)
        var settings = AppSettings.defaults
        settings.unit = .iops
        settings.testCount = 7
        settings.tests[0].blockSizeBytes = 512

        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test func flashMemoryPresetUsesShortMeasureAndLongInterval() {
        let preset = AppSettings.flashMemory
        #expect(preset.measureTime == 1)
        #expect(preset.intervalTime == 30)
        #expect(preset.tests.map(\.label) == AppSettings.defaults.tests.map(\.label))
        #expect(preset.validate().isEmpty)
    }

    @Test func nvmePresetIsDefinedButUnavailable() {
        #expect(AppSettings.nvmeAvailable == false)
        #expect(AppSettings.nvme.tests[2].queues == 32)
        #expect(AppSettings.nvme.tests[2].threads == 16)
    }
}
