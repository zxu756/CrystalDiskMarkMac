import SwiftUI

public enum Theme {
    public static let window = Color(hex: 0x1B1B1B)
    public static let panel = Color(hex: 0x242424)
    public static let track = Color(hex: 0x333333)
    public static let read = Color(hex: 0x4CD964)
    public static let write = Color(hex: 0x32ADE6)
    public static let primaryText = Color(hex: 0xF5F5F5)
    public static let secondaryText = Color(hex: 0x9A9A9A)

    public static let numberFont = Font.system(size: 32, weight: .bold, design: .monospaced)
    public static let labelFont = Font.system(size: 11, weight: .semibold)
    public static let bodyFont = Font.system(size: 12)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
