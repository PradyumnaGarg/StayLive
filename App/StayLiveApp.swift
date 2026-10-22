import SwiftUI

@main
struct StayLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryStore.shared
    @StateObject private var desktop = DesktopController.shared
    @StateObject private var lockScreen = LockScreenController.shared
    @StateObject private var screenSaver = ScreenSaverController.shared

    var body: some Scene {
        Window("StayLive", id: "library") {
            LibraryView()
                .environmentObject(library)
                .environmentObject(desktop)
                .environmentObject(lockScreen)
                .environmentObject(screenSaver)
                .frame(minWidth: 860, minHeight: 540)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(library)
                .environmentObject(desktop)
                .environmentObject(lockScreen)
                .environmentObject(screenSaver)
        } label: {
            Image(systemName: desktop.isUserPaused ? "pause.rectangle" : "play.rectangle.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(desktop)
                .environmentObject(lockScreen)
                .environmentObject(screenSaver)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DesktopController.shared.start()
        ScreenSaverController.shared.upgradeIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
