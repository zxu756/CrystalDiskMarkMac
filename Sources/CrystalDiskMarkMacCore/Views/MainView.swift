import SwiftUI

public struct MainView: View {
    @ObservedObject private var model: BenchmarkViewModel
    @Environment(\.uiScale) private var uiScale

    public init(model: BenchmarkViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: uiScale.value(4)) {
            topBar
                .frame(height: uiScale.value(36), alignment: .top)
                .disabled(model.isRunning)

            VStack(spacing: uiScale.value(4)) {
                ForEach(Array(model.displaySettings.tests.enumerated()), id: \.element.id) { index, test in
                    ResultRowView(
                        test: test,
                        read: model.results["\(test.id)-read"],
                        write: model.results["\(test.id)-write"],
                        unit: model.displaySettings.unit,
                        action: { model.run(testIndex: index) }
                    )
                }
            }
            .disabled(model.isRunning)

            Spacer(minLength: 0)
            statusBar
        }
        .padding(uiScale.value(7))
        .frame(width: uiScale.value(480), height: uiScale.value(300))
        .background(Theme.window)
        .sheet(isPresented: $model.showSettings) {
            SettingsView(
                settings: model.settings,
                availableBytes: model.targetFreeBytes,
                onSave: { settings in
                    model.saveSettings(settings)
                    model.showSettings = false
                },
                onCancel: {
                    model.showSettings = false
                }
            )
        }
        .sheet(isPresented: $model.showAbout) {
            AboutView()
        }
        .onChange(of: model.settings) { _, _ in
            model.persistSettings()
        }
        .alert("CrystalDiskMark Mac", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK") {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: uiScale.value(5)) {
            menuPicker(
                "Count",
                value: "\(model.settings.testCount)x",
                selection: $model.settings.testCount,
                options: Array(1...9),
                width: uiScale.value(48)
            ) { "\($0)x" }

            menuPicker(
                "Size",
                value: AppSettings.testSizeLabel(for: model.settings.testSizeIndex),
                selection: $model.settings.testSizeIndex,
                options: Array(0..<AppSettings.testSizeMiB.count),
                width: uiScale.value(76)
            ) { AppSettings.testSizeLabel(for: $0) }

            VStack(alignment: .leading, spacing: uiScale.value(1)) {
                Text("Volume")
                    .font(uiScale.font(11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    ForEach(model.volumes) { volume in
                        Button("\(volume.name) — \(formatBytes(volume.freeBytes)) free of \(formatBytes(volume.totalBytes))") {
                            model.selectVolume(volume)
                        }
                    }
                    Divider()
                    Button("Select Folder…") {
                        model.chooseFolder()
                    }
                } label: {
                    Text(model.targetDisplayName)
                        .font(uiScale.font(12))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: uiScale.value(92), alignment: .leading)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(width: uiScale.value(92), alignment: .leading)
            }

            menuPicker(
                "Unit",
                value: model.settings.unit.label,
                selection: $model.settings.unit,
                options: BenchmarkUnit.allCases,
                width: uiScale.value(64)
            ) { $0.label }

            Spacer(minLength: 0)

            Button("All") {
                model.runAll()
            }
            .font(uiScale.font(12))
            .buttonStyle(.borderedProminent)
            .tint(Theme.read)
            .controlSize(.regular)
            .disabled(model.isRunning)
        }
    }

    private var statusBar: some View {
        VStack(spacing: uiScale.value(3)) {
            HStack(spacing: uiScale.value(6)) {
                Text(model.statusText.isEmpty ? "Ready" : model.statusText)
                    .font(uiScale.font(12))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.isRunning {
                    Text("\(Int(model.progress * 100))%")
                        .font(uiScale.font(12))
                        .foregroundStyle(Theme.secondaryText)
                    Button("Stop") {
                        model.stop()
                    }
                    .font(uiScale.font(12))
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(Theme.read)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func menuPicker<T: Hashable>(
        _ title: String,
        value: String,
        selection: Binding<T>,
        options: [T],
        width: CGFloat,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: uiScale.value(1)) {
            Text(title)
                .font(uiScale.font(11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack(spacing: uiScale.value(2)) {
                    Text(value)
                        .font(uiScale.font(12))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: uiScale.value(7), weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(width: width, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .frame(width: width, alignment: .leading)
        }
    }
}
