import AppKit
import Foundation

public enum VolumeError: LocalizedError, Equatable {
    case notWritable(URL)
    case notEnoughSpace(required: UInt64, available: UInt64)

    public var errorDescription: String? {
        switch self {
        case .notWritable(let url):
            return "The selected location is not writable: \(url.path)"
        case .notEnoughSpace(let required, let available):
            return "Not enough free space: need \(required) bytes, \(available) available."
        }
    }
}

public struct VolumeCatalog {
    public static let freeSpaceMargin: UInt64 = 512 * 1024 * 1024

    private let fileManager: FileManager
    private let cachesDirectory: URL

    public init(fileManager: FileManager = .default, cachesDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.cachesDirectory = cachesDirectory ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first!
    }

    public func mountedVolumes() -> [VolumeInfo] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey,
            .volumeIsRootFileSystemKey
        ]

        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsLocal == true else {
                return nil
            }

            let freeBytes = UInt64(max(0, values.volumeAvailableCapacityForImportantUsage ?? 0))
            let totalBytes = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let isBoot = values.volumeIsRootFileSystem ?? (url.path == "/")
            let name = isBoot ? "Boot volume" : (values.volumeName ?? url.lastPathComponent)

            return VolumeInfo(
                url: url,
                name: name,
                freeBytes: freeBytes,
                totalBytes: totalBytes,
                isBoot: isBoot
            )
        }
    }

    public func resolveTarget(for volume: VolumeInfo, requiredBytes: UInt64 = 0) throws -> URL {
        let target = volume.isBoot
            ? cachesDirectory.appendingPathComponent("CrystalDiskMarkMac", isDirectory: true)
            : volume.url.appendingPathComponent("CrystalDiskMarkMac", isDirectory: true)

        do {
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw VolumeError.notWritable(volume.url)
        }

        guard fileManager.isWritableFile(atPath: target.path) else {
            throw VolumeError.notWritable(volume.url)
        }

        if requiredBytes > 0 {
            let available = try freeBytes(at: target)
            try validateFreeSpace(requiredBytes: requiredBytes, available: available)
        }

        return target
    }

    public func validateFreeSpace(at url: URL, requiredBytes: UInt64) throws {
        guard fileManager.isWritableFile(atPath: url.path) else {
            throw VolumeError.notWritable(url)
        }
        let available = try freeBytes(at: url)
        try validateFreeSpace(requiredBytes: requiredBytes, available: available)
    }

    public func freeBytes(at url: URL) throws -> UInt64 {
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return UInt64(max(0, capacity))
        }

        let attributes = try fileManager.attributesOfFileSystem(forPath: url.path)
        if let size = attributes[.systemFreeSize] as? NSNumber {
            return size.uint64Value
        }
        return 0
    }

    @MainActor
    public func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func validateFreeSpace(requiredBytes: UInt64, available: UInt64) throws {
        guard requiredBytes <= UInt64.max - Self.freeSpaceMargin else {
            throw VolumeError.notEnoughSpace(required: requiredBytes, available: available)
        }

        let requiredWithMargin = requiredBytes + Self.freeSpaceMargin
        if available < requiredWithMargin {
            throw VolumeError.notEnoughSpace(required: requiredWithMargin, available: available)
        }
    }
}
