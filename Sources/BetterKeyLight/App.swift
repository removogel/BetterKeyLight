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
            Image(nsImage: MenuBarIcon.image(on: store.isOn))
        }
        .menuBarExtraStyle(.window)

        Window("BetterKeyLight Settings", id: "settings") {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}
