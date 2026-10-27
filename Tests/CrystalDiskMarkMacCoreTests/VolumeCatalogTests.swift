import Testing
import Foundation
@testable import CrystalDiskMarkMacCore

struct VolumeCatalogTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cdm-volume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func bootTargetPathIncludesAppDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let catalog = VolumeCatalog(cachesDirectory: caches)
        #expect(catalog.bootTargetPath == caches.appendingPathComponent("CrystalDiskMarkMac").path)
    }

    @Test func bootVolumeResolvesToInjectedCachesDirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let catalog = VolumeCatalog(cachesDirectory: caches)
        let boot = VolumeInfo(
            url: URL(fileURLWithPath: "/"),
            name: "Macintosh HD",
            freeBytes: 100_000_000_000,
            totalBytes: 200_000_000_000,
            isBoot: true
        )

        let target = try catalog.resolveTarget(for: boot)
        #expect(target.path == caches.appendingPathComponent("CrystalDiskMarkMac").path)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func writableVolumeResolvesToSubdirectory() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let catalog = VolumeCatalog(cachesDirectory: root.appendingPathComponent("Caches"))
        let volume = VolumeInfo(
            url: root,
            name: "External",
            freeBytes: 100_000_000_000,
            totalBytes: 200_000_000_000,
            isBoot: false
        )

        let target = try catalog.resolveTarget(for: volume)
        #expect(target.path == root.appendingPathComponent("CrystalDiskMarkMac").path)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func readOnlyVolumeThrowsNotWritable() throws {
        let root = try makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        let catalog = VolumeCatalog(cachesDirectory: root.appendingPathComponent("Caches"))
        let volume = VolumeInfo(
            url: root,
            name: "Read Only",
            freeBytes: 100_000_000_000,
            totalBytes: 200_000_000_000,
            isBoot: false
        )

        #expect(throws: VolumeError.self) {
            _ = try catalog.resolveTarget(for: volume)
        }
    }

    @Test func freeBytesIsPositive() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let catalog = VolumeCatalog(cachesDirectory: root.appendingPathComponent("Caches"))
        #expect(try catalog.freeBytes(at: root) > 0)
    }

    @Test func insufficientSpaceThrows() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let catalog = VolumeCatalog(cachesDirectory: root.appendingPathComponent("Caches"))
        let volume = VolumeInfo(
            url: root,
            name: "External",
            freeBytes: 100_000_000,
            totalBytes: 200_000_000,
            isBoot: false
        )

        #expect(throws: VolumeError.self) {
            _ = try catalog.resolveTarget(for: volume, requiredBytes: UInt64.max / 2)
        }
    }
}
