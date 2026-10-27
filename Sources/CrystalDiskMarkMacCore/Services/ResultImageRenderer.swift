import AppKit
import SwiftUI

@MainActor
public enum ResultImageRenderer {
    public static func render(model: BenchmarkViewModel) -> NSImage? {
        let renderer = ImageRenderer(
            content: MainView(model: model)
                .frame(width: 480, height: 300)
        )
        renderer.proposedSize = ProposedViewSize(width: 480, height: 300)
        renderer.scale = 2
        return renderer.nsImage
    }
}
