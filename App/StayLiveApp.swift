import SwiftUI

@main
struct StayLiveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = LibraryStore.shared
    @StateObject private var desktop = DesktopController.shared
    @StateObject private var lockScreen = LockScreenController.shared
    @StateObject private var screenSaver = ScreenSaverController.shared
    @StateObject private var nav = AppNavigation.shared
    @StateObject private var builtIns = BuiltInLibrary.shared
    @StateObject private var toasts = ToastCenter.shared

    var body: some Scene {
        Window("StayLive", id: "library") {
            RootView()
                .environmentObject(nav)
                .environmentObject(builtIns)
                .environmentObject(toasts)
                .environmentObject(library)
                .environmentObject(desktop)
                .environmentObject(lockScreen)
                .environmentObject(screenSaver)
                .frame(minWidth: 860, minHeight: 540)
                .preferredColorScheme(.dark)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { nav.showSettings = true }
                    .keyboardShortcut(",")
            }
        }

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
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        DesktopController.shared.start()
        ScreenSaverController.shared.upgradeIfNeeded()
        BuiltInLibrary.shared.ensureInstalled()
        LockScreenController.shared.migrateIfNeeded()
        LockScreenController.shared.repairSelectionIfNeeded()
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopController.shared.endPreview() }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ScreenSaverController.shared.refreshSelection()
                LockScreenController.shared.refresh()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
