import AppKit
import SwiftUI
import CrystalDiskMarkMacCore

@main
struct CrystalDiskMarkMacApp: App {
    @StateObject private var model = BenchmarkViewModel()

    private let baseWidth: CGFloat = 480
    private let baseHeight: CGFloat = 300
    private let zoom: CGFloat = 1.5

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(
                    width: baseWidth * zoom,
                    height: baseHeight * zoom,
                    alignment: .topLeading
                )
                .background(Theme.window)
                .clipped()
        }
        .defaultSize(width: baseWidth * zoom, height: baseHeight * zoom)
        .windowResizability(.contentSize)
        .commands {
            AppCommands(model: model)
        }
    }
}

struct AppCommands: Commands {
    let model: BenchmarkViewModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CrystalDiskMark Mac") {
                model.showAbout = true
            }
        }

        CommandGroup(after: .newItem) {
            Button("Copy") {
                model.copyResults()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(model.isRunning)
            Button("Save (Text)…") {
                model.saveText()
            }
            .disabled(model.isRunning)
            Button("Save (Image)…") {
                model.saveImage()
            }
            .disabled(model.isRunning)
            Divider()
            Button("Quit CrystalDiskMark Mac") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        CommandMenu("Settings") {
            Button("Default") {
                model.applyPreset(.defaults)
            }
            .disabled(model.isRunning)
            Button("Flash Memory") {
                model.applyPreset(.flashMemory)
            }
            .disabled(model.isRunning)
            Divider()
            Button("Queues & Threads…") {
                model.showSettings = true
            }
            .disabled(model.isRunning)
        }

        CommandMenu("Profile") {
            Button("Default") {
                update { $0.profile = .defaultProfile }
            }
            .disabled(model.isRunning)
            Button("Peak Performance") {}
                .disabled(true)
            Button("Real World Performance") {}
                .disabled(true)
            Button("Demonstration") {}
                .disabled(true)
        }

        CommandMenu("Test Mode") {
            Button("Default (Random)") {
                update { $0.dataPattern = .random }
            }
            .disabled(model.isRunning)
            Button("All 0x00 (0 Fill)") {
                update { $0.dataPattern = .zero }
            }
            .disabled(model.isRunning)
        }

        CommandMenu("Benchmark") {
            Button("Run All") {
                model.runAll()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(model.isRunning)
            Button("Stop") {
                model.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(!model.isRunning)
            Divider()
            Button("Read & Write") {
                update { $0.benchmarkMode = .readWrite }
            }
            .disabled(model.isRunning)
            Button("Read") {
                update { $0.benchmarkMode = .readOnly }
            }
            .disabled(model.isRunning)
            Button("Write") {
                update { $0.benchmarkMode = .writeOnly }
            }
            .disabled(model.isRunning)
        }

        CommandMenu("Theme") {
            Button("Default") {}
                .disabled(true)
        }

        CommandMenu("Language") {
            Button("English") {}
                .disabled(true)
        }

        CommandGroup(replacing: .help) {
            Button("CrystalDiskMark Mac Help") {
                model.showAbout = true
            }
        }
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        var settings = model.settings
        mutate(&settings)
        model.saveSettings(settings)
    }
}
