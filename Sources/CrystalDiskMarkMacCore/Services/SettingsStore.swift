import Foundation

public struct SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        let fallback = AppSettings.defaults
        var settings = fallback

        settings.testCount = int(forKey: "TestCount", fallback: fallback.testCount, range: 1...9)
        settings.testSizeIndex = int(
            forKey: "TestSize",
            fallback: fallback.testSizeIndex,
            range: 0..<AppSettings.testSizeMiB.count
        )

        if let raw = defaults.object(forKey: "TestUnit") as? Int,
           let unit = BenchmarkUnit(rawValue: raw) {
            settings.unit = unit
        }
        if let raw = defaults.string(forKey: "TestData"),
           let pattern = DataPattern(rawValue: raw) {
            settings.dataPattern = pattern
        }
        if let raw = defaults.string(forKey: "Benchmark"),
           let mode = BenchmarkMode(rawValue: raw) {
            settings.benchmarkMode = mode
        }
        if let raw = defaults.string(forKey: "Profile"),
           let profile = BenchmarkProfile(rawValue: raw) {
            settings.profile = profile
        }
        if let path = defaults.string(forKey: "TargetPath"), !path.isEmpty {
            settings.targetPath = path
        }
        if AppSettings.measureTimeOptions.contains(defaults.object(forKey: "MeasureTime") as? Int ?? -1) {
            settings.measureTime = defaults.integer(forKey: "MeasureTime")
        }
        if AppSettings.intervalTimeOptions.contains(defaults.object(forKey: "IntervalTime") as? Int ?? -1) {
            settings.intervalTime = defaults.integer(forKey: "IntervalTime")
        }

        var tests = fallback.tests
        for index in tests.indices {
            let typeRaw = defaults.object(forKey: "BenchType\(index)") as? Int
            let type: BenchmarkType
            if let typeRaw {
                type = typeRaw == 1 ? .random : .sequential
            } else {
                type = tests[index].type
            }

            var blockSizeBytes = tests[index].blockSizeBytes
            if let sizeKiB = defaults.object(forKey: "BenchSize\(index)") as? Double,
               sizeKiB.isFinite,
               sizeKiB > 0,
               sizeKiB <= Double(UInt64.max) / 1_024.0 {
                let bytes = UInt64((sizeKiB * 1_024.0).rounded())
                if AppSettings.blockSizeOptions.contains(bytes) {
                    blockSizeBytes = bytes
                }
            }

            var queues = int(forKey: "BenchQueues\(index)", fallback: tests[index].queues, range: 1...32)
            var threads = int(forKey: "BenchThreads\(index)", fallback: tests[index].threads, range: 1...16)
            if queues * threads > 128 {
                queues = tests[index].queues
                threads = tests[index].threads
            }

            tests[index] = TestDefinition(
                id: tests[index].id,
                type: type,
                blockSizeBytes: blockSizeBytes,
                queues: queues,
                threads: threads
            )
        }
        settings.tests = tests

        return settings
    }

    public func save(_ settings: AppSettings) {
        defaults.set(settings.testCount, forKey: "TestCount")
        defaults.set(settings.testSizeIndex, forKey: "TestSize")
        defaults.set(settings.unit.rawValue, forKey: "TestUnit")
        defaults.set(settings.measureTime, forKey: "MeasureTime")
        defaults.set(settings.intervalTime, forKey: "IntervalTime")
        defaults.set(settings.dataPattern.rawValue, forKey: "TestData")
        defaults.set(settings.benchmarkMode.rawValue, forKey: "Benchmark")
        defaults.set(settings.profile.rawValue, forKey: "Profile")
        defaults.set(settings.targetPath, forKey: "TargetPath")

        for (index, test) in settings.tests.enumerated() {
            defaults.set(test.type == .random ? 1 : 0, forKey: "BenchType\(index)")
            defaults.set(Double(test.blockSizeBytes) / 1_024.0, forKey: "BenchSize\(index)")
            defaults.set(test.queues, forKey: "BenchQueues\(index)")
            defaults.set(test.threads, forKey: "BenchThreads\(index)")
        }
    }

    private func int(forKey key: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let value = defaults.object(forKey: key) as? Int, range.contains(value) else {
            return fallback
        }
        return value
    }

    private func int(forKey key: String, fallback: Int, range: Range<Int>) -> Int {
        guard let value = defaults.object(forKey: key) as? Int, range.contains(value) else {
            return fallback
        }
        return value
    }
}
