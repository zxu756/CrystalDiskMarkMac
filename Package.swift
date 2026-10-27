// swift-tools-version: 6.0
import Foundation
import PackageDescription

let cltTestingMacros = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSwiftSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: cltTestingMacros)
    ? [.unsafeFlags(["-load-plugin-library", cltTestingMacros])]
    : []

let package = Package(
    name: "CrystalDiskMarkMac",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(name: "CrystalDiskMarkMacCore", targets: ["CrystalDiskMarkMacCore"]),
        .executable(name: "CrystalDiskMarkMac", targets: ["CrystalDiskMarkMac"])
    ],
    targets: [
        .target(
            name: "CrystalDiskMarkMacCore",
            path: "Sources/CrystalDiskMarkMacCore"
        ),
        .executableTarget(
            name: "CrystalDiskMarkMac",
            dependencies: ["CrystalDiskMarkMacCore"],
            path: "Sources/CrystalDiskMarkMac"
        ),
        .target(
            name: "DiskMarkEngineCore",
            path: "Sources/DiskMarkEngineCore",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "DiskMarkEngine",
            dependencies: ["DiskMarkEngineCore"],
            path: "Sources/DiskMarkEngine"
        ),
        .testTarget(
            name: "CrystalDiskMarkMacCoreTests",
            dependencies: ["CrystalDiskMarkMacCore"],
            path: "Tests/CrystalDiskMarkMacCoreTests",
            swiftSettings: testSwiftSettings
        )
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
