import SwiftUI
import AppKit

@main
struct BetterKeyLightApp: App {
    @StateObject private var store = LightStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
        } label: {
            Image(systemName: store.isOn ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)

        Window("KeyLight Einstellungen", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}
