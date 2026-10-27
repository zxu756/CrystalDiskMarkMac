import Foundation

public struct ValidationIssue: Equatable, Sendable {
    public let field: String
    public let message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var testCount: Int
    public var testSizeIndex: Int
    public var unit: BenchmarkUnit
    public var tests: [TestDefinition]
    public var measureTime: Int
    public var intervalTime: Int
    public var dataPattern: DataPattern
    public var benchmarkMode: BenchmarkMode
    public var profile: BenchmarkProfile
    public var targetPath: String

    public init(
        testCount: Int,
        testSizeIndex: Int,
        unit: BenchmarkUnit,
        tests: [TestDefinition],
        measureTime: Int,
        intervalTime: Int,
        dataPattern: DataPattern,
        benchmarkMode: BenchmarkMode,
        profile: BenchmarkProfile,
        targetPath: String
    ) {
        self.testCount = testCount
        self.testSizeIndex = testSizeIndex
        self.unit = unit
        self.tests = tests
        self.measureTime = measureTime
        self.intervalTime = intervalTime
        self.dataPattern = dataPattern
        self.benchmarkMode = benchmarkMode
        self.profile = profile
        self.targetPath = targetPath
    }

    public static let testSizeMiB: [UInt64] = [
        16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536
    ]

    public static let measureTimeOptions = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 60]
    public static let intervalTimeOptions = [0, 1, 3, 5, 10, 30, 60, 180, 300, 600]
    public static let blockSizeOptions: [UInt64] = [
        512, 1_024, 2_048, 4_096, 8_192, 16_384, 32_768, 65_536,
        131_072, 262_144, 524_288, 1_048_576, 2_097_152, 4_194_304, 8_388_608
    ]

    public static let defaultTests: [TestDefinition] = [
        TestDefinition(id: "seq-1m-q8t1", type: .sequential, blockSizeBytes: 1_048_576, queues: 8, threads: 1),
        TestDefinition(id: "seq-1m-q1t1", type: .sequential, blockSizeBytes: 1_048_576, queues: 1, threads: 1),
        TestDefinition(id: "rnd-4k-q32t1", type: .random, blockSizeBytes: 4_096, queues: 32, threads: 1),
        TestDefinition(id: "rnd-4k-q1t1", type: .random, blockSizeBytes: 4_096, queues: 1, threads: 1)
    ]

    public static let nvmeAvailable = false

    public static var defaults: AppSettings {
        AppSettings(
            testCount: 3,
            testSizeIndex: 6,
            unit: .mbps,
            tests: defaultTests,
            measureTime: 5,
            intervalTime: 5,
            dataPattern: .random,
            benchmarkMode: .readWrite,
            profile: .defaultProfile,
            targetPath: defaultTargetPath
        )
    }

    public static var flashMemory: AppSettings {
        var settings = AppSettings.defaults
        settings.measureTime = 1
        settings.intervalTime = 30
        return settings
    }

    public static var nvme: AppSettings {
        AppSettings(
            testCount: 3,
            testSizeIndex: 6,
            unit: .mbps,
            tests: [
                TestDefinition(id: "seq-1m-q8t1", type: .sequential, blockSizeBytes: 1_048_576, queues: 8, threads: 1),
                TestDefinition(id: "seq-128k-q32t1", type: .sequential, blockSizeBytes: 131_072, queues: 32, threads: 1),
                TestDefinition(id: "rnd-4k-q32t16", type: .random, blockSizeBytes: 4_096, queues: 32, threads: 16),
                TestDefinition(id: "rnd-4k-q1t1", type: .random, blockSizeBytes: 4_096, queues: 1, threads: 1)
            ],
            measureTime: 5,
            intervalTime: 5,
            dataPattern: .random,
            benchmarkMode: .readWrite,
            profile: .defaultProfile,
            targetPath: defaultTargetPath
        )
    }

    public func preservingTargetPath(_ path: String) -> AppSettings {
        var copy = self
        copy.targetPath = path
        return copy
    }

    public var testSizeBytes: UInt64 {
        guard AppSettings.testSizeMiB.indices.contains(testSizeIndex) else { return 0 }
        return AppSettings.testSizeMiB[testSizeIndex] * 1_048_576
    }

    public var testSizeLabel: String {
        AppSettings.testSizeLabel(for: testSizeIndex)
    }

    public static func testSizeLabel(for index: Int) -> String {
        guard testSizeMiB.indices.contains(index) else { return "0 MiB" }
        let mib = testSizeMiB[index]
        if mib >= 1_024 && mib % 1_024 == 0 {
            return "\(mib / 1_024) GiB"
        }
        return "\(mib) MiB"
    }

    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if !(1...9).contains(testCount) {
            issues.append(ValidationIssue(field: "testCount", message: "Test count must be 1–9."))
        }
        if !AppSettings.testSizeMiB.indices.contains(testSizeIndex) {
            issues.append(ValidationIssue(field: "testSizeIndex", message: "Test size is invalid."))
        }
        if !AppSettings.measureTimeOptions.contains(measureTime) {
            issues.append(ValidationIssue(field: "measureTime", message: "Measure time is invalid."))
        }
        if !AppSettings.intervalTimeOptions.contains(intervalTime) {
            issues.append(ValidationIssue(field: "intervalTime", message: "Interval time is invalid."))
        }
        if tests.count != 4 {
            issues.append(ValidationIssue(field: "tests", message: "Exactly four tests are required."))
        }
        if targetPath.isEmpty {
            issues.append(ValidationIssue(field: "targetPath", message: "A target folder is required."))
        }

        for test in tests {
            if !AppSettings.blockSizeOptions.contains(test.blockSizeBytes) {
                issues.append(ValidationIssue(field: "blockSizeBytes", message: "Block size is invalid."))
            }
            if !(1...32).contains(test.queues) {
                issues.append(ValidationIssue(field: "queues", message: "Queues must be 1–32."))
            }
            if !(1...16).contains(test.threads) {
                issues.append(ValidationIssue(field: "threads", message: "Threads must be 1–16."))
            }
            if test.queues * test.threads > 128 {
                issues.append(ValidationIssue(field: "threads", message: "Queues × threads must not exceed 128."))
            }
        }

        return issues
    }

    private static var defaultTargetPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/CrystalDiskMarkMac", isDirectory: true)
            .path
    }
}
