import Foundation

public enum ResultFormatter {
    public static func valueString(
        result: BenchmarkResult,
        unit: BenchmarkUnit,
        blockSizeBytes: UInt64
    ) -> String {
        _ = blockSizeBytes

        switch unit {
        case .mbps:
            return result.mbps >= 1_000_000
                ? String(format: "%.0f", result.mbps)
                : String(format: "%.2f", result.mbps)
        case .gbps:
            return String(format: "%.3f", result.mbps / 1_000)
        case .iops:
            return result.iops >= 1_000_000
                ? String(format: "%.0f", result.iops)
                : String(format: "%.2f", result.iops)
        case .microseconds:
            if result.mbps <= 0 {
                return String(format: "%.2f", 0.0)
            }
            return result.latencyUs >= 1_000_000
                ? String(format: "%.0f", result.latencyUs)
                : String(format: "%.2f", result.latencyUs)
        }
    }

    public static func meterRatio(result: BenchmarkResult, unit: BenchmarkUnit) -> Double {
        let value: Double

        if unit == .microseconds {
            guard result.latencyUs > 0.0000000001 else { return 0 }
            value = 1.0 - (1.0 / 6.0) * log10(result.latencyUs)
        } else {
            guard result.mbps > 0.1 else { return 0 }
            value = (1.0 / 6.0) * log10(result.mbps * 10.0)
        }

        return min(max(value, 0), 1)
    }

    public static func textBlock(
        settings: AppSettings,
        results: [String: BenchmarkResult],
        date: Date,
        osVersion: String,
        volumeName: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var lines: [String] = [
            "CrystalDiskMark Mac 0.1.0",
            "Based on CrystalDiskMark (C) 2007-2026 hiyohiyo",
            "Not affiliated with CrystalMark.",
            "",
            "[Read]"
        ]

        for test in settings.tests {
            if let result = results["\(test.id)-read"] {
                lines.append(line(test: test, result: result))
            } else {
                lines.append(missingLine(test))
            }
        }

        lines.append("")
        lines.append("[Write]")

        for test in settings.tests {
            if let result = results["\(test.id)-write"] {
                lines.append(line(test: test, result: result))
            } else {
                lines.append(missingLine(test))
            }
        }

        lines.append("")
        lines.append("Profile: \(settings.profile.displayName)")
        lines.append("Test: \(settings.testSizeLabel) (x\(settings.testCount))")
        lines.append("Mode: \(modeLabel(settings.benchmarkMode))")
        lines.append("Time: \(formatter.string(from: date))")
        lines.append("Date: \(dateFormatter.string(from: date))")
        lines.append("OS: \(osVersion)")
        lines.append("Volume: \(volumeName)")

        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(test: TestDefinition, result: BenchmarkResult) -> String {
        let metrics = String(
            format: "%9.3f MB/s [%9.1f IOPS] <%9.2f us>",
            result.mbps,
            result.iops,
            result.latencyUs
        )
        let stale = result.isStale ? " [STALE]" : ""
        return "  \(test.label) (Q=\(test.queues), T=\(test.threads)): \(metrics)\(stale)"
    }

    private static func missingLine(_ test: TestDefinition) -> String {
        "  \(test.label) (Q=\(test.queues), T=\(test.threads)): N/A"
    }

    private static func modeLabel(_ mode: BenchmarkMode) -> String {
        switch mode {
        case .readWrite: return "Read+Write"
        case .readOnly: return "Read"
        case .writeOnly: return "Write"
        }
    }
}
