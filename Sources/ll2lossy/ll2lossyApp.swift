import SwiftUI
import AppKit

@main
struct ll2lossyApp: App {
    @StateObject private var settings = AppSettings()

    init() {
        NSApplication.shared.applicationIconImage = Self.applicationIcon()
    }

    private static func applicationIcon() -> NSImage {
        if let url = Bundle.module.url(forResource: "LosslessToMP3", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            return icon
        }
        return AppIcon.make()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}
