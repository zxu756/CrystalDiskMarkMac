import AppKit
import SwiftUI
import CrystalDiskMarkMacCore

@main
struct CrystalDiskMarkMacApp: App {
    @StateObject private var model = BenchmarkViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
        }
        .defaultSize(width: 480, height: 300)
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
            Button("Save (Text)…") {
                model.saveText()
            }
            Button("Save (Image)…") {
                model.saveImage()
            }
            Divider()
            Button("Quit CrystalDiskMark Mac") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        CommandMenu("Settings") {
            Button("Default") {
                model.saveSettings(.defaults)
            }
            Button("Flash Memory") {
                model.saveSettings(.flashMemory)
            }
            Divider()
            Button("Queues & Threads…") {
                model.showSettings = true
            }
        }

        CommandMenu("Profile") {
            Button("Default") {
                update { $0.profile = .defaultProfile }
            }
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
            Button("All 0x00 (0 Fill)") {
                update { $0.dataPattern = .zero }
            }
        }

        CommandMenu("Benchmark") {
            Button("Run All") {
                model.runAll()
            }
            .keyboardShortcut("r", modifiers: .command)
            Button("Stop") {
                model.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            Divider()
            Button("Read & Write") {
                update { $0.benchmarkMode = .readWrite }
            }
            Button("Read") {
                update { $0.benchmarkMode = .readOnly }
            }
            Button("Write") {
                update { $0.benchmarkMode = .writeOnly }
            }
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
