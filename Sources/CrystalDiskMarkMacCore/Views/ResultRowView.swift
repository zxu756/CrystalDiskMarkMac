import SwiftUI

public struct ResultRowView: View {
    public let test: TestDefinition
    public let read: BenchmarkResult?
    public let write: BenchmarkResult?
    public let unit: BenchmarkUnit
    public let action: () -> Void

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
        HStack(spacing: 6) {
            Button(action: action) {
                VStack(spacing: 0) {
                    Text(labelParts.0)
                        .font(.system(size: 11, weight: .semibold))
                    Text(labelParts.1)
                        .font(.system(size: 10, weight: .regular))
                }
                .foregroundStyle(Theme.primaryText)
                .frame(width: 82, height: 40)
                .background(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Theme.track, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
        .padding(1)
        .background(Theme.panel.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var labelParts: (String, String) {
        let parts = test.label.split(separator: " ").map(String.init)
        return (parts.first ?? test.label, parts.dropFirst().joined(separator: " "))
    }

    private var helpText: String {
        "\(test.label)\nBlock: \(test.blockSizeBytes) bytes\nQueues: \(test.queues)\nThreads: \(test.threads)"
    }
}
