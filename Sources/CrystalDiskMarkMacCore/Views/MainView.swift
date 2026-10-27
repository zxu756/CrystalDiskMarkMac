import SwiftUI

public struct MainView: View {
    @ObservedObject private var model: BenchmarkViewModel

    public init(model: BenchmarkViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 4) {
            topBar
                .frame(height: 32, alignment: .top)

            VStack(spacing: 4) {
                ForEach(Array(model.settings.tests.enumerated()), id: \.element.id) { index, test in
                    ResultRowView(
                        test: test,
                        read: model.results["\(test.id)-read"],
                        write: model.results["\(test.id)-write"],
                        unit: model.settings.unit,
                        action: { model.run(testIndex: index) }
                    )
                }
            }

            Spacer(minLength: 0)
            statusBar
        }
        .padding(7)
        .frame(width: 480, height: 300)
        .background(Theme.window)
        .sheet(isPresented: $model.showSettings) {
            placeholderSheet(title: "Queues & Threads", detail: "Settings UI arrives in the next task.")
        }
        .sheet(isPresented: $model.showAbout) {
            placeholderSheet(
                title: "CrystalDiskMark Mac",
                detail: "Based on CrystalDiskMark by hiyohiyo. Not affiliated with CrystalMark."
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 5) {
            menuPicker(
                "Count",
                value: "\(model.settings.testCount)x",
                selection: $model.settings.testCount,
                options: Array(1...9),
                width: 48
            ) { "\($0)x" }

            menuPicker(
                "Size",
                value: AppSettings.testSizeLabel(for: model.settings.testSizeIndex),
                selection: $model.settings.testSizeIndex,
                options: Array(0..<AppSettings.testSizeMiB.count),
                width: 70
            ) { AppSettings.testSizeLabel(for: $0) }

            VStack(alignment: .leading, spacing: 1) {
                Text("Volume")
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.secondaryText)
                Menu {
                    Button("Select Folder…") {}
                } label: {
                    Text(model.selectedVolume?.name ?? "Boot volume")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 92, alignment: .leading)
            }

            menuPicker(
                "Unit",
                value: model.settings.unit.label,
                selection: $model.settings.unit,
                options: BenchmarkUnit.allCases,
                width: 64
            ) { $0.label }

            Spacer(minLength: 0)

            Button("All") {
                model.runAll()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.read)
            .controlSize(.small)
            .disabled(model.isRunning)
        }
    }

    private var statusBar: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(model.statusText.isEmpty ? "Ready" : model.statusText)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.isRunning {
                    Text("\(Int(model.progress * 100))%")
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Stop") {
                        model.stop()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(Theme.read)
        }
    }

    private func menuPicker<T: Hashable>(
        _ title: String,
        value: String,
        selection: Binding<T>,
        options: [T],
        width: CGFloat,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.secondaryText)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(label(option)) {
                        selection.wrappedValue = option
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(value)
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(width: width, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .frame(width: width, alignment: .leading)
        }
    }

    private func placeholderSheet(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(detail)
                .font(Theme.bodyFont)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(width: 420, height: 300)
        .background(Theme.window)
    }
}
