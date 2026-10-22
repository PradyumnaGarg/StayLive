import AVFoundation
import ScreenSaver
import os

@objc(StayLiveSaverView)
final class StayLiveSaverView: ScreenSaverView {
    private static var systemSaverActive: Bool?
    private static var stateObservers: [NSObjectProtocol] = []
    private static let activeNotification = Notification.Name("StayLiveSaverSystemActive")

    private static func observeSystemState() {
        guard stateObservers.isEmpty else { return }
        let dnc = DistributedNotificationCenter.default()
        stateObservers.append(dnc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { _ in
            systemSaverActive = true
            NotificationCenter.default.post(name: activeNotification, object: nil)
        })
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            stateObservers.append(dnc.addObserver(forName: .init(name), object: nil, queue: .main) { _ in
                systemSaverActive = false
            })
        }
    }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
        animationTimeInterval = 1
        Self.observeSystemState()
        NotificationCenter.default.addObserver(self, selector: #selector(systemBecameActive), name: Self.activeNotification, object: nil)
        load()
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.willstop", "com.apple.screensaver.didstop"] {
            dnc.addObserver(self, selector: #selector(screenSaverEnding), name: .init(name), object: nil)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenSaverEnding), name: NSWorkspace.screensDidSleepNotification, object: nil)
    }

    private let log = Logger(subsystem: Bundle(for: StayLiveSaverView.self).bundleIdentifier ?? "StayLive.saver", category: "audio")

    @objc private func screenSaverEnding(_ note: Notification) {
        log.notice("stop signal \(note.name.rawValue, privacy: .public) playing=\(self.player.rate != 0)")
        fadeOutAndPause()
    }

    private var wantsSound = false

    @objc private func systemBecameActive() {
        guard wantsSound, player.rate != 0, player.isMuted, claimAudio() else { return }
        player.isMuted = false
        log.notice("sound on after system start")
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func load() {
        guard let resources = Bundle(for: Self.self).resourceURL,
              let settings = NSDictionary(contentsOf: resources.appendingPathComponent("settings.plist")) as? [String: Any],
              let name = settings["video"] as? String else { return }
        let url = resources.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        soundEnabled = settings["sound"] as? Bool ?? false
        player.isMuted = true
        targetVolume = Float(settings["volume"] as? Double ?? 0.6)
        player.volume = targetVolume
    }

    private var targetVolume: Float = 0.6
    private var fadeTimer: Timer?

    private func fadeOutAndPause() {
        guard fadeTimer == nil, player.rate != 0 else { return }
        guard !player.isMuted else { stopPlayback(); return }
        let steps = 10
        var step = 0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            self.player.volume = self.targetVolume * Float(max(0, steps - step)) / Float(steps)
            if step >= steps {
                timer.invalidate()
                self.fadeTimer = nil
                self.stopPlayback()
            }
        }
    }

    private var orphanCheck: Timer?

    private static var screenIsLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func scheduleOrphanCheck() {
        orphanCheck?.invalidate()
        orphanCheck = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            guard let self, Self.systemSaverActive != true, !Self.screenIsLocked, self.player.rate != 0 else { return }
            self.log.notice("unconfirmed start while unlocked, stopping")
            self.stopPlayback()
        }
    }

    private func stopPlayback() {
        orphanCheck?.invalidate()
        orphanCheck = nil
        wantsSound = false
        player.pause()
        player.isMuted = true
        player.volume = targetVolume
        releaseAudio()
    }

    private var soundEnabled = false

    private var isOnMainScreen: Bool {
        guard let main = NSScreen.screens.first else { return true }
        if let screen = window?.screen { return screen.frame == main.frame }
        return abs(bounds.width - main.frame.width) < 2 && abs(bounds.height - main.frame.height) < 2
    }

    private var audioLockFD: Int32 = -1

    private func claimAudio() -> Bool {
        if audioLockFD >= 0 { return true }
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("staylive-audio.lock")
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { return false }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { audioLockFD = fd; return true }
        close(fd)
        return false
    }

    private func releaseAudio() {
        guard audioLockFD >= 0 else { return }
        flock(audioLockFD, LOCK_UN)
        close(audioLockFD)
        audioLockFD = -1
    }

    override func startAnimation() {
        super.startAnimation()
        if !isPreview && Self.systemSaverActive == false {
            log.notice("ignored start: system screen saver not active")
            return
        }
        let onMain = isOnMainScreen
        wantsSound = !isPreview && soundEnabled && onMain
        let claimed = wantsSound && Self.systemSaverActive == true && claimAudio()
        fadeTimer?.invalidate()
        fadeTimer = nil
        player.volume = targetVolume
        player.isMuted = !claimed
        log.notice("start preview=\(self.isPreview) sound=\(claimed)")
        player.play()
        if !isPreview && Self.systemSaverActive != true { scheduleOrphanCheck() }
    }

    override func stopAnimation() {
        super.stopAnimation()
        log.notice("stop signal stopAnimation playing=\(self.player.rate != 0)")
        fadeOutAndPause()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { log.notice("stop signal removedFromWindow"); fadeTimer?.invalidate(); fadeTimer = nil; stopPlayback() }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        releaseAudio()
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
}
