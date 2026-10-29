import SwiftUI

public struct UIScale: Equatable, Sendable {
    public var factor: CGFloat

    public init(factor: CGFloat = 1) {
        self.factor = factor
    }

    public func value(_ value: CGFloat) -> CGFloat {
        value * factor
    }

    public func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * factor, weight: weight, design: design)
    }
}

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue = UIScale()
}

public extension EnvironmentValues {
    var uiScale: UIScale {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}
