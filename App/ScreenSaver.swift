import AppKit

@MainActor
final class ScreenSaverController: ObservableObject {
    static let shared = ScreenSaverController()

    @Published private(set) var currentID: UUID?
    @Published private(set) var isInstalled = false
    @Published var errorMessage: String?
    @Published var soundEnabled = UserDefaults.standard.bool(forKey: "saverSound") {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "saverSound"); rewriteSettings() }
    }
    @Published var volume: Double = UserDefaults.standard.object(forKey: "saverVolume") as? Double ?? 0.6 {
        didSet { UserDefaults.standard.set(volume, forKey: "saverVolume") }
    }

    static let installedURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Screen Savers/StayLive.saver")
    private var embeddedURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("StayLive.saver") }
    private var resources: URL { Self.installedURL.appendingPathComponent("Contents/Resources") }

    private init() {
        if let s = UserDefaults.standard.string(forKey: "screenSaverID") { currentID = UUID(uuidString: s) }
        isInstalled = FileManager.default.fileExists(atPath: Self.installedURL.path)
    }

    func set(_ w: Wallpaper) {
        do {
            try installBundleIfNeeded()
            let fm = FileManager.default
            for old in (try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent.hasPrefix("current.") {
                try? fm.removeItem(at: old)
            }
            let name = "current.\(LibraryStore.shared.videoURL(w).pathExtension)"
            try fm.copyItem(at: LibraryStore.shared.videoURL(w), to: resources.appendingPathComponent(name))
            currentID = w.id
            UserDefaults.standard.set(w.id.uuidString, forKey: "screenSaverID")
            try writeSettings(video: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyVolume() { rewriteSettings() }

    func upgradeIfNeeded() {
        guard isInstalled, let embeddedURL,
              Bundle(url: embeddedURL)?.infoDictionary?["CFBundleVersion"] as? String
                != Bundle(url: Self.installedURL)?.infoDictionary?["CFBundleVersion"] as? String,
              let w = LibraryStore.shared.item(currentID) else { return }
        set(w)
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
    }

    private func rewriteSettings() {
        guard isInstalled,
              let dict = NSDictionary(contentsOf: resources.appendingPathComponent("settings.plist")),
              let video = dict["video"] as? String else { return }
        try? writeSettings(video: video)
    }

    private func writeSettings(video: String) throws {
        let dict: NSDictionary = ["video": video, "sound": soundEnabled, "volume": volume]
        try dict.write(to: resources.appendingPathComponent("settings.plist"))
        try resign()
    }

    private func installBundleIfNeeded() throws {
        guard let embeddedURL else { throw CocoaError(.fileNoSuchFile) }
        let fm = FileManager.default
        let embeddedVersion = Bundle(url: embeddedURL)?.infoDictionary?["CFBundleVersion"] as? String
        let installedVersion = Bundle(url: Self.installedURL)?.infoDictionary?["CFBundleVersion"] as? String
        if fm.fileExists(atPath: Self.installedURL.path), embeddedVersion == installedVersion { return }
        try fm.createDirectory(at: Self.installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: Self.installedURL)
        try fm.copyItem(at: embeddedURL, to: Self.installedURL)
        isInstalled = true
    }

    private func resign() throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["--force", "--sign", "-", Self.installedURL.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}
