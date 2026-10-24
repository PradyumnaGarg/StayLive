import AppKit
import AVFoundation
import IOKit.ps
import ServiceManagement

final class WallpaperWindow: NSWindow {
    let screenID: CGDirectDisplayID
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    init(screen: NSScreen) {
        screenID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(playerLayer)
        contentView = view

        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        setFrame(screen.frame, display: true)
    }

    func load(_ url: URL?) {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        guard let url else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    func setAudio(muted: Bool, volume: Float) {
        player.isMuted = muted
        player.volume = volume
    }

    func setPlaying(_ playing: Bool) {
        if playing, player.rate == 0 { player.play() }
        if !playing, player.rate != 0 { player.pause() }
    }
}

@MainActor
final class DesktopController: ObservableObject {
    static let shared = DesktopController()

    @Published private(set) var currentID: UUID?
    @Published private(set) var isUserPaused = UserDefaults.standard.bool(forKey: "userPaused")
    @Published private(set) var isPlaying = false
    @Published var pauseOnBattery = UserDefaults.standard.bool(forKey: "pauseOnBattery") {
        didSet { UserDefaults.standard.set(pauseOnBattery, forKey: "pauseOnBattery"); updatePlayback() }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }
    @Published var launchAtLoginError: String?
    @Published var soundEnabled = UserDefaults.standard.bool(forKey: "soundEnabled") {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled"); applyAudio() }
    }
    @Published var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.6 {
        didSet { UserDefaults.standard.set(volume, forKey: "volume"); applyAudio() }
    }

    private var windows: [WallpaperWindow] = []
    private var screenLocked = false
    private var screensAsleep = false
    private var onBattery = false
    private var batteryTimer: Timer?

    private init() {
        if let s = UserDefaults.standard.string(forKey: "desktopWallpaperID") { currentID = UUID(uuidString: s) }
    }

    func start() {
        if !UserDefaults.standard.bool(forKey: "didConfigureLaunchAtLogin") {
            UserDefaults.standard.set(true, forKey: "didConfigureLaunchAtLogin")
            if SMAppService.mainApp.status != .enabled { launchAtLogin = true }
        }
        rebuildWindows()
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildWindows() }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = true; self?.updatePlayback() }
        }
        wnc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = false; self?.updatePlayback() }
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = true; self?.updatePlayback() }
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenLocked = false; self?.updatePlayback() }
        }
        refreshBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBattery() }
        }
    }

    @Published private(set) var previewID: UUID?

    func setWallpaper(_ id: UUID?, announce: Bool = true) {
        previewID = nil
        currentID = id
        UserDefaults.standard.set(id?.uuidString, forKey: "desktopWallpaperID")
        loadWindows()
        if announce, let w = LibraryStore.shared.item(id) {
            ToastCenter.shared.show("Desktop set to \(w.name)", symbol: "desktopcomputer")
        }
    }

    func startPreview(_ id: UUID) {
        previewID = id
        loadWindows()
    }

    func endPreview() {
        guard previewID != nil else { return }
        previewID = nil
        loadWindows()
        ToastCenter.shared.show("Preview ended", message: "Your desktop is back. Press Apply to keep a wallpaper.",
                                symbol: "eye", style: .info)
    }

    private func loadWindows() {
        let url = LibraryStore.shared.item(previewID ?? currentID).map { LibraryStore.shared.videoURL($0) }
        windows.forEach { $0.load(url) }
        applyAudio()
        updatePlayback()
    }

    private func applyAudio() {
        let mainID = NSScreen.screens.first.flatMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
        for w in windows {
            w.setAudio(muted: !(soundEnabled && w.screenID == mainID), volume: Float(volume))
        }
    }

    func togglePause() {
        isUserPaused.toggle()
        UserDefaults.standard.set(isUserPaused, forKey: "userPaused")
        updatePlayback()
    }

    private func rebuildWindows() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0) }
        let url = LibraryStore.shared.item(previewID ?? currentID).map { LibraryStore.shared.videoURL($0) }
        for w in windows {
            w.load(url)
            w.orderBack(nil)
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: w)
        }
        applyAudio()
        updatePlayback()
    }

    @objc private func occlusionChanged() { updatePlayback() }

    private func refreshBattery() {
        let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let type = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
        let battery = type == kIOPMBatteryPowerKey
        if battery != onBattery { onBattery = battery; updatePlayback() }
    }

    private func updatePlayback() {
        let active = currentID != nil && !isUserPaused && !screenLocked && !screensAsleep && !(pauseOnBattery && onBattery)
        var anyPlaying = false
        for w in windows {
            let play = active && w.occlusionState.contains(.visible)
            w.setPlaying(play)
            anyPlaying = anyPlaying || play
        }
        isPlaying = anyPlaying
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
