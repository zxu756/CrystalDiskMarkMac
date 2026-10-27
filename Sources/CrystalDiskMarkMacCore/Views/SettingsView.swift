import SwiftUI

private final class SettingsDraft: ObservableObject {
    @Published var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }
}

public struct SettingsView: View {
    @ObservedObject private var draft: SettingsDraft
    public let onSave: (AppSettings) -> Void
    public let onCancel: () -> Void
    private let availableBytes: UInt64?

    public init(
        settings: AppSettings,
        availableBytes: UInt64? = nil,
        onSave: @escaping (AppSettings) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.draft = SettingsDraft(settings: settings)
        self.availableBytes = availableBytes
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 10) {
            Text("Queues & Threads")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            columnHeaders

            ForEach(0..<4, id: \.self) { index in
                testRow(index)
            }

            Divider().overlay(Theme.track)

            HStack(spacing: 12) {
                Picker("Measure Time", selection: $draft.settings.measureTime) {
                    ForEach(AppSettings.measureTimeOptions, id: \.self) { value in
                        Text("\(value)s").tag(value)
                    }
                }
                Picker("Interval Time", selection: $draft.settings.intervalTime) {
                    ForEach(AppSettings.intervalTimeOptions, id: \.self) { value in
                        Text("\(value)s").tag(value)
                    }
                }
                Picker("Data", selection: $draft.settings.dataPattern) {
                    Text("Random").tag(DataPattern.random)
                    Text("0Fill").tag(DataPattern.zero)
                }
            }
            .font(Theme.bodyFont)
            .foregroundStyle(Theme.primaryText)

            HStack(spacing: 8) {
                Button("Default") {
                    draft.settings = AppSettings.defaults.preservingTargetPath(draft.settings.targetPath)
                }
                Button("Flash Memory") {
                    draft.settings = AppSettings.flashMemory.preservingTargetPath(draft.settings.targetPath)
                }
                Button("NVMe SSD") {}
                    .disabled(true)
                Spacer()
            }
            .controlSize(.small)

            if let issue = validationIssues.first {
                Text(issue.message)
                    .font(Theme.bodyFont)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("OK") {
                    onSave(draft.settings)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!validationIssues.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520, height: 380)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("Test").frame(width: 48, alignment: .leading)
            Text("Type").frame(width: 64, alignment: .leading)
            Text("Size").frame(width: 74, alignment: .leading)
            Text("Queues").frame(width: 76, alignment: .leading)
            Text("Threads").frame(width: 76, alignment: .leading)
            Spacer()
        }
        .font(Theme.labelFont)
        .foregroundStyle(Theme.secondaryText)
    }

    private func testRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Text("Test \(index + 1)")
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 48, alignment: .leading)

            Picker("", selection: $draft.settings.tests[index].type) {
                Text("SEQ").tag(BenchmarkType.sequential)
                Text("RND").tag(BenchmarkType.random)
            }
            .labelsHidden()
            .frame(width: 64)

            Picker("", selection: $draft.settings.tests[index].blockSizeBytes) {
                ForEach(AppSettings.blockSizeOptions, id: \.self) { bytes in
                    Text(blockSizeLabel(bytes)).tag(bytes)
                }
            }
            .labelsHidden()
            .frame(width: 74)

            Picker("", selection: $draft.settings.tests[index].queues) {
                ForEach(1...32, id: \.self) { value in
                    Text("Q\(value)").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 76)

            Picker("", selection: $draft.settings.tests[index].threads) {
                ForEach(1...16, id: \.self) { value in
                    Text("T\(value)").tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 76)

            Spacer()
        }
        .font(Theme.bodyFont)
    }

    private var validationIssues: [ValidationIssue] {
        var issues = draft.settings.validate()

        if let availableBytes {
            let required = draft.settings.testSizeBytes
            let margin = VolumeCatalog.freeSpaceMargin
            if required > UInt64.max - margin || availableBytes < required + margin {
                issues.append(ValidationIssue(
                    field: "testSize",
                    message: "Not enough free space for the test file and 512 MiB safety margin."
                ))
            }
        }

        return issues
    }

    private func blockSizeLabel(_ bytes: UInt64) -> String {
        if bytes >= 1_048_576 {
            return "\(bytes / 1_048_576)M"
        }
        if bytes >= 1_024 {
            return "\(bytes / 1_024)K"
        }
        return "\(bytes)B"
    }
}
