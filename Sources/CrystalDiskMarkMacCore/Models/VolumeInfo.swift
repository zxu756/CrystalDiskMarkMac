import Foundation

public struct VolumeInfo: Identifiable, Equatable, Sendable {
    public let url: URL
    public let name: String
    public let freeBytes: UInt64
    public let totalBytes: UInt64
    public let isBoot: Bool

    public var id: String { url.path }

    public init(url: URL, name: String, freeBytes: UInt64, totalBytes: UInt64, isBoot: Bool) {
        self.url = url
        self.name = name
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.isBoot = isBoot
    }
}
