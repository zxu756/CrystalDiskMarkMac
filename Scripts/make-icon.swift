#!/usr/bin/env swift

import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let masterSVG = resources.appendingPathComponent("AppIcon-1024.png")

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: masterSVG)

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0x1B / 255.0, green: 0x1B / 255.0, blue: 0x1B / 255.0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).fill()

NSColor(calibratedRed: 0x24 / 255.0, green: 0x24 / 255.0, blue: 0x24 / 255.0, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 160, yRadius: 160).fill()

let green = NSColor(calibratedRed: 0x4C / 255.0, green: 0xD9 / 255.0, blue: 0x64 / 255.0, alpha: 1)
let blue = NSColor(calibratedRed: 0x32 / 255.0, green: 0xAD / 255.0, blue: 0xE6 / 255.0, alpha: 1)

green.setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 250, width: 170, height: 430), xRadius: 36, yRadius: 36).fill()

blue.setFill()
NSBezierPath(roundedRect: NSRect(x: 604, y: 250, width: 170, height: 430), xRadius: 36, yRadius: 36).fill()

NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 250, y: 760, width: 524, height: 70), xRadius: 35, yRadius: 35).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not render icon\n", stderr)
    exit(1)
}

try png.write(to: masterSVG)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    let output = iconset.appendingPathComponent(name)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixels)", "\(pixels)", masterSVG.path, "--out", output.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fputs("sips failed for \(name)\n", stderr)
        exit(1)
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
try? FileManager.default.removeItem(at: masterSVG)
print("wrote Resources/AppIcon.icns")
