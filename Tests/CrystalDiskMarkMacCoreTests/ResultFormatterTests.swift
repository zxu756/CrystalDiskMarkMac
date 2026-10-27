import Testing
import AppKit
import Foundation
@testable import CrystalDiskMarkMacCore

struct ResultFormatterTests {
    private func result(
        mbps: Double,
        iops: Double = 0,
        latencyUs: Double = 0
    ) -> BenchmarkResult {
        BenchmarkResult(
            testID: "seq",
            operation: .read,
            mbps: mbps,
            iops: iops,
            latencyUs: latencyUs
        )
    }

    @Test func formatsMbps() {
        #expect(ResultFormatter.valueString(result: result(mbps: 1_250_000), unit: .mbps, blockSizeBytes: 4096) == "1250000")
        #expect(ResultFormatter.valueString(result: result(mbps: 123.456), unit: .mbps, blockSizeBytes: 4096) == "123.46")
    }

    @Test func formatsGbps() {
        #expect(ResultFormatter.valueString(result: result(mbps: 1234.6), unit: .gbps, blockSizeBytes: 4096) == "1.235")
    }

    @Test func formatsIops() {
        #expect(ResultFormatter.valueString(result: result(mbps: 100, iops: 1_500_000), unit: .iops, blockSizeBytes: 4096) == "1500000")
        #expect(ResultFormatter.valueString(result: result(mbps: 100, iops: 244.140625), unit: .iops, blockSizeBytes: 4096) == "244.14")
    }

    @Test func formatsMicroseconds() {
        #expect(ResultFormatter.valueString(result: result(mbps: 0, latencyUs: 0), unit: .microseconds, blockSizeBytes: 4096) == "0.00")
        #expect(ResultFormatter.valueString(result: result(mbps: 100, latencyUs: 1_500_000), unit: .microseconds, blockSizeBytes: 4096) == "1500000")
        #expect(ResultFormatter.valueString(result: result(mbps: 100, latencyUs: 42.7), unit: .microseconds, blockSizeBytes: 4096) == "42.70")
    }

    @Test func meterRatioIsClamped() {
        #expect(ResultFormatter.meterRatio(result: result(mbps: 0), unit: .mbps) == 0)
        #expect(ResultFormatter.meterRatio(result: result(mbps: 1_000_000_000), unit: .mbps) == 1)
        #expect(ResultFormatter.meterRatio(result: result(mbps: 100, latencyUs: 1e-12), unit: .microseconds) == 0)
        #expect(ResultFormatter.meterRatio(result: result(mbps: 100, latencyUs: 1_000_000), unit: .microseconds) == 0)
    }

    @Test func textBlockContainsExpectedSections() {
        var results: [String: BenchmarkResult] = [:]
        let ids = ["seq-1m-q8t1", "seq-1m-q1t1", "rnd-4k-q32t1", "rnd-4k-q1t1"]
        for id in ids {
            results["\(id)-read"] = BenchmarkResult(testID: id, operation: .read, mbps: 100, iops: 1_000, latencyUs: 10)
            results["\(id)-write"] = BenchmarkResult(testID: id, operation: .write, mbps: 80, iops: 800, latencyUs: 12)
        }

        let text = ResultFormatter.textBlock(
            settings: .defaults,
            results: results,
            date: Date(timeIntervalSince1970: 0),
            osVersion: "macOS 27.0.1",
            volumeName: "Boot volume"
        )

        #expect(text.contains("[Read]"))
        #expect(text.contains("[Write]"))
        #expect(text.contains("SEQ1M Q8T1"))
        #expect(text.contains("Profile: Default"))
        #expect(text.contains("Test: 1 GiB (x3)"))
        #expect(text.contains("Mode: Read+Write"))
        #expect(text.contains("Time:"))
        #expect(text.contains("Date:"))
        #expect(text.contains("OS:"))
        #expect(text.contains("Volume:"))
        #expect(text.contains("CrystalDiskMark"))
    }

    @Test func partialResultsUseNAAndStaleMarker() {
        var result = BenchmarkResult(testID: "seq-1m-q8t1", operation: .read, mbps: 100, iops: 10, latencyUs: 5)
        result.isStale = true

        let text = ResultFormatter.textBlock(
            settings: .defaults,
            results: ["seq-1m-q8t1-read": result],
            date: Date(timeIntervalSince1970: 0),
            osVersion: "macOS 27.0.1",
            volumeName: "Boot volume"
        )

        #expect(text.contains("N/A"))
        #expect(text.contains("[STALE]"))
    }

    @MainActor
    @Test func rendersImageAtTwoTimesScale() throws {
        let image = ResultImageRenderer.render(model: .preview)
        let unwrapped = try #require(image)
        let data = try #require(unwrapped.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide == 960)
        #expect(bitmap.pixelsHigh == 600)
    }
}
