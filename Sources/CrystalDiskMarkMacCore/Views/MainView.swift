import SwiftUI

public struct MainView: View {
    public init() {}

    public var body: some View {
        ZStack {
            Theme.window
            VStack(spacing: 8) {
                Text("CrystalDiskMark Mac")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("macOS benchmark replica")
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 480, height: 300)
    }
}
