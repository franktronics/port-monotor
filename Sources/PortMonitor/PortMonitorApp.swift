import ServiceManagement
import SwiftUI

@main
struct PortMonitorApp: App {
    @StateObject private var store: PortMonitorStore

    init() {
        _store = StateObject(wrappedValue: PortMonitorStore())
        LaunchAtLogin.registerIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra("Port Monitor", systemImage: "network") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

private enum LaunchAtLogin {
    static func registerIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }

        do {
            try service.register()
        } catch {
            NSLog("Unable to enable launch at login: %@", error.localizedDescription)
        }
    }
}
