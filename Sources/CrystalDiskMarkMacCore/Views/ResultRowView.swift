import SwiftUI

public struct ResultRowView: View {
    public let test: TestDefinition
    public let read: BenchmarkResult?
    public let write: BenchmarkResult?
    public let unit: BenchmarkUnit
    public let action: () -> Void

    @Environment(\.uiScale) private var uiScale

    public init(
        test: TestDefinition,
        read: BenchmarkResult?,
        write: BenchmarkResult?,
        unit: BenchmarkUnit,
        action: @escaping () -> Void
    ) {
        self.test = test
        self.read = read
        self.write = write
        self.unit = unit
        self.action = action
    }

    public var body: some View {
        HStack(spacing: uiScale.value(6)) {
            Button(action: action) {
                VStack(spacing: 0) {
                    Text(labelParts.0)
                        .font(uiScale.font(11, weight: .semibold))
                    Text(labelParts.1)
                        .font(uiScale.font(10))
                }
                .foregroundStyle(Theme.primaryText)
                .frame(width: uiScale.value(82), height: uiScale.value(40))
                .background(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: uiScale.value(4))
                        .stroke(Theme.track, lineWidth: max(1, uiScale.value(1)))
                )
                .clipShape(RoundedRectangle(cornerRadius: uiScale.value(4)))
            }
            .buttonStyle(.plain)
            .help(helpText)

            MeterView(
                title: "Read",
                result: read,
                unit: unit,
                blockSizeBytes: test.blockSizeBytes,
                accent: Theme.read
            )
            .frame(maxWidth: .infinity)
            .help(helpText)

            MeterView(
                title: "Write",
                result: write,
                unit: unit,
                blockSizeBytes: test.blockSizeBytes,
                accent: Theme.write
            )
            .frame(maxWidth: .infinity)
            .help(helpText)
        }
        .padding(uiScale.value(1))
        .background(Theme.panel.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: uiScale.value(4)))
    }

    private var labelParts: (String, String) {
        let parts = test.label.split(separator: " ").map(String.init)
        return (parts.first ?? test.label, parts.dropFirst().joined(separator: " "))
    }

    private var helpText: String {
        "\(test.label)\nBlock: \(test.blockSizeBytes) bytes\nQueues: \(test.queues)\nThreads: \(test.threads)"
    }
}
