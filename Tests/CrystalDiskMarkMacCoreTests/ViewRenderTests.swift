import Testing
import SwiftUI
@testable import CrystalDiskMarkMacCore

@MainActor
@Test func mainViewRendersAtExpectedSize() {
    let model = BenchmarkViewModel.preview
    let renderer = ImageRenderer(content: MainView(model: model).frame(width: 480, height: 300))
    renderer.proposedSize = .init(width: 480, height: 300)

    let image = renderer.nsImage
    #expect(image != nil)
    #expect(image?.size == CGSize(width: 480, height: 300))
    #expect(image?.tiffRepresentation?.isEmpty == false)
}
