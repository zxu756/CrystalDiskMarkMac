import SwiftUI
import CrystalDiskMarkMacCore

@main
struct CrystalDiskMarkMacApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowResizability(.contentSize)
    }
}
