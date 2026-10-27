import SwiftUI

public struct AboutView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Text("CrystalDiskMark Mac")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.primaryText)

            Text("Version 0.1.0")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)

            Text("Based on CrystalDiskMark by hiyohiyo.\nMIT licensed. Not affiliated with CrystalMark.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)

            Text("Write results are not fsynced and include the drive's volatile cache, matching CrystalDiskMark's default behavior.")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 280)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }
}
