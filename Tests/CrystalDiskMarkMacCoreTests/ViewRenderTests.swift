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

@MainActor
@Test func mainViewRendersAt150Percent() {
    let model = BenchmarkViewModel.preview
    let content = MainView(model: model)
        .environment(\.uiScale, UIScale(factor: 1.5))
        .frame(width: 720, height: 450)
    let renderer = ImageRenderer(content: content)
    renderer.proposedSize = .init(width: 720, height: 450)

    let image = renderer.nsImage
    #expect(image != nil)
    #expect(image?.size == CGSize(width: 720, height: 450))
    #expect(image?.tiffRepresentation?.isEmpty == false)
}

@MainActor
@Test func settingsViewRenders() {
    let renderer = ImageRenderer(
        content: SettingsView(
            settings: .defaults,
            onSave: { _ in },
            onCancel: {}
        )
        .frame(width: 520, height: 380)
    )
    renderer.proposedSize = .init(width: 520, height: 380)

    let image = renderer.nsImage
    #expect(image != nil)
    #expect(image?.size == CGSize(width: 520, height: 380))
}
