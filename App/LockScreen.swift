import AppKit
import AVFoundation
import VideoToolbox

enum AerialEncoderError: LocalizedError {
    case noVideoTrack, sessionFailed(OSStatus), encodeFailed(OSStatus), writeFailed(String), incomplete(Int, Int), cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The video has no video track."
        case .sessionFailed(let s): return "Couldn't start the hardware encoder (\(s))."
        case .encodeFailed(let s): return "Encoding failed (\(s))."
        case .writeFailed(let m): return "Couldn't write the converted video: \(m)"
        case .incomplete(let w, let t): return "Only \(w) of \(t) frames were written."
        case .cancelled: return "Conversion cancelled."
        }
    }
}

final class AerialEncoder {
    static let width = 3840, height = 2160
    static let fps: Int32 = 240

    static func targetSeconds(forSourceDuration d: Double) -> Double {
        guard d > 0 else { return 60 }
        if d >= 180 { return 180 }
        return (60 / d).rounded(.up) * d
    }

    static func encode(source: URL, to outputURL: URL, seconds: Double,
                       isCancelled: () -> Bool, progress: (Double) -> Void) throws {
        let totalFrames = Int(seconds * Double(fps))
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Converting lock screen video")
        defer { ProcessInfo.processInfo.endActivity(activity) }

        let asset = AVURLAsset(url: source)
        guard let track = asset.tracks(withMediaType: .video).first else { throw AerialEncoderError.noVideoTrack }
        let repeats = max(1, Int((Double(fps) / Double(max(track.nominalFrameRate, 1))).rounded()))

        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.movieTimeScale = 240000

        var sessionOut: VTCompressionSession?
        let created = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
            compressionSessionOut: &sessionOut)
        guard created == noErr, let session = sessionOut else { throw AerialEncoderError.sessionFailed(created) }
        defer { VTCompressionSessionInvalidate(session) }

        let props: [CFString: Any] = [
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_HEVC_Main10_AutoLevel,
            kVTCompressionPropertyKey_RealTime: false,
            kVTCompressionPropertyKey_ExpectedFrameRate: fps,
            kVTCompressionPropertyKey_AllowFrameReordering: true,
            kVTCompressionPropertyKey_AllowOpenGOP: false,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: 1200,
            kVTCompressionPropertyKey_AverageBitRate: 20_000_000,
            kVTCompressionPropertyKey_BaseLayerFrameRate: 30,
            "NumberOfTemporalLayers" as CFString: 4,
            "TemporalIDNestingFlag" as CFString: true,
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_sRGB,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]
        for (k, v) in props { VTSessionSetProperty(session, key: k, value: v as CFTypeRef) }
        VTCompressionSessionPrepareToEncodeFrames(session)

        var transferOut: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transferOut)
        guard let transfer = transferOut else { throw AerialEncoderError.sessionFailed(-1) }
        defer { VTPixelTransferSessionInvalidate(transfer) }
        VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Letterbox)

        var readers: [AVAssetReader] = []
        func makeReader() throws -> AVAssetReaderTrackOutput {
            let reader = try AVAssetReader(asset: asset)
            let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            ])
            reader.add(out)
            reader.startReading()
            readers.append(reader)
            return out
        }

        func fit(_ pb: CVPixelBuffer) throws -> CVPixelBuffer {
            if CVPixelBufferGetWidth(pb) == width && CVPixelBufferGetHeight(pb) == height { return pb }
            var outPB: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &outPB)
            guard let outPB else { throw AerialEncoderError.encodeFailed(-1) }
            let s = VTPixelTransferSessionTransferImage(transfer, from: pb, to: outPB)
            if s != noErr { throw AerialEncoderError.encodeFailed(s) }
            return outPB
        }

        let lock = NSLock()
        var pending: [CMSampleBuffer] = []
        var encodeError: OSStatus = noErr
        var input: AVAssetWriterInput?
        var written = 0

        func drain() throws {
            guard let input else { return }
            let batch: [CMSampleBuffer] = lock.withLock { let b = pending; pending.removeAll(); return b }
            for sb in batch {
                while !input.isReadyForMoreMediaData { usleep(1000) }
                if !input.append(sb) { throw AerialEncoderError.writeFailed(writer.error?.localizedDescription ?? "unknown") }
                written += 1
            }
        }

        var readerOut = try makeReader()
        var current: CVPixelBuffer?
        var used = repeats
        var frameIndex = 0
        var emptyReads = 0

        while frameIndex < totalFrames {
            if isCancelled() { writer.cancelWriting(); throw AerialEncoderError.cancelled }
            if used >= repeats {
                guard let src = readerOut.copyNextSampleBuffer(), let srcPB = CMSampleBufferGetImageBuffer(src) else {
                    emptyReads += 1
                    if emptyReads > 2 { throw AerialEncoderError.noVideoTrack }
                    readerOut = try makeReader()
                    continue
                }
                emptyReads = 0
                current = try fit(srcPB)
                used = 0
            }
            used += 1
            let pts = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            let status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: current!, presentationTimeStamp: pts,
                duration: CMTime(value: 1, timescale: fps), frameProperties: nil, infoFlagsOut: nil) { st, _, sb in
                if st != noErr { lock.withLock { encodeError = st }; return }
                guard let sb else { return }
                if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) as NSArray?,
                   let dict = arr.firstObject as? NSMutableDictionary,
                   let tli = dict[kCMSampleAttachmentKey_HEVCTemporalLevelInfo] as? [String: Any],
                   let level = tli[kCMHEVCTemporalLevelInfoKey_TemporalLevel as String] as? Int, level >= 1 {
                    dict[kCMSampleAttachmentKey_HEVCTemporalSubLayerAccess] = true
                }
                lock.withLock { pending.append(sb) }
            }
            if status != noErr { throw AerialEncoderError.encodeFailed(status) }
            if let e = lock.withLock({ encodeError == noErr ? nil : encodeError }) { throw AerialEncoderError.encodeFailed(e) }

            if input == nil {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: pts)
                if let first = lock.withLock({ pending.first }) {
                    let inp = AVAssetWriterInput(mediaType: .video, outputSettings: nil,
                                                 sourceFormatHint: CMSampleBufferGetFormatDescription(first))
                    inp.expectsMediaDataInRealTime = false
                    inp.mediaTimeScale = 240000
                    writer.add(inp)
                    writer.startWriting()
                    writer.startSession(atSourceTime: .zero)
                    input = inp
                }
            }
            try drain()
            frameIndex += 1
            if frameIndex % 120 == 0 { progress(Double(frameIndex) / Double(totalFrames)) }
        }

        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        try drain()
        input?.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw AerialEncoderError.writeFailed(writer.error?.localizedDescription ?? "unknown") }
        if written != totalFrames { throw AerialEncoderError.incomplete(written, totalFrames) }
        progress(1)
    }
}

enum LockScreenError: LocalizedError {
    case noAerialSelected, aerialNotDownloaded, noBackup, installFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAerialSelected: return "Pick any Aerial as your wallpaper in System Settings → Wallpaper first."
        case .aerialNotDownloaded: return "The selected Aerial hasn't been downloaded yet. Let it play once in System Settings, then try again."
        case .noBackup: return "No backup of Apple's original video was found."
        case .installFailed(let m): return m
        }
    }
}

enum AerialFiles {
    static let wallpaperRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper")
    static let markerKey = "StayLive.wallpaperID"

    static func selectedAerialID() -> String? {
        let url = wallpaperRoot.appendingPathComponent("Store/Index.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let all = root["AllSpacesAndDisplays"] as? [String: Any] else { return nil }
        for key in ["Idle", "Desktop"] {
            guard let content = (all[key] as? [String: Any])?["Content"] as? [String: Any],
                  let choice = (content["Choices"] as? [[String: Any]])?.first,
                  (choice["Provider"] as? String) == "com.apple.wallpaper.choice.aerials",
                  let configData = choice["Configuration"] as? Data,
                  let config = try? PropertyListSerialization.propertyList(from: configData, format: nil) as? [String: Any],
                  let id = config["assetID"] as? String else { continue }
            return id
        }
        return nil
    }

    static func aerialName(_ id: String) -> String? {
        let url = wallpaperRoot.appendingPathComponent("aerials/manifest/entries.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else { return nil }
        return assets.first { $0["id"] as? String == id }?["accessibilityLabel"] as? String
    }

    static func videoURL(_ id: String) -> URL {
        wallpaperRoot.appendingPathComponent("aerials/videos/\(id).mov")
    }

    static func backupURL(_ id: String) -> URL { AppPaths.backups.appendingPathComponent("\(id).mov") }

    static func getXattr(_ url: URL, _ name: String) -> Data? {
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, size, 0, 0) }
        return read == size ? data : nil
    }

    static func setXattr(_ url: URL, _ name: String, _ value: Data) -> Bool {
        value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, 0) } == 0
    }

    static func installedWallpaperID(_ id: String) -> UUID? {
        getXattr(videoURL(id), markerKey).flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init)
    }

    static func restartWallpaperAgent() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["WallpaperAgent"]
        try? p.run()
        p.waitUntilExit()
    }
}

final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ v: Bool) { lock.withLock { value = v } }
    func get() -> Bool { lock.withLock { value } }
}

@MainActor
final class LockScreenController: ObservableObject {
    static let shared = LockScreenController()

    @Published private(set) var convertingID: UUID?
    @Published private(set) var progress: Double = 0
    @Published private(set) var queue: [UUID] = []
    @Published private(set) var installingID: UUID?
    @Published private(set) var requestedID: UUID?
    @Published private(set) var conversionStart: Date?
    @Published var errorMessage: String?
    @Published private(set) var installedID: UUID?
    @Published private(set) var aerialID: String?
    @Published private(set) var aerialName: String?
    @Published private(set) var catalogEnabled = false
    @Published private(set) var catalogCount = 0

    private var cancelToken = CancelToken()
    private let installQueue = DispatchQueue(label: "StayLive.install")
    private let library = LibraryStore.shared

    private init() { refresh() }

    func refresh() {
        catalogEnabled = AerialCatalog.isEnabled
        aerialID = AerialCatalog.selectedDesktopAssetID() ?? AerialFiles.selectedAerialID()
        aerialName = aerialID.flatMap(AerialFiles.aerialName)
        installedID = aerialID.flatMap(AerialFiles.installedWallpaperID)
        catalogCount = catalogEnabled ? catalogEntries().count : 0
        mergeAppleListIfUpdated()
    }

    private func catalogEntries() -> [CatalogEntry] {
        library.items.compactMap { w in
            guard let video = library.aerialURL(w), FileManager.default.fileExists(atPath: video.path) else { return nil }
            return CatalogEntry(id: w.id, name: w.name, video: video, thumbnail: library.thumbnailURL(w))
        }
    }

    private func mergeAppleListIfUpdated() {
        guard catalogEnabled,
              let modified = try? FileManager.default.attributesOfItem(atPath: AerialCatalog.appleManifest.path)[.modificationDate] as? Date
        else { return }
        let synced = UserDefaults.standard.object(forKey: "catalogSyncedAppleList") as? Date ?? .distantPast
        guard modified > synced else { return }
        resyncCatalog(restart: false)
    }

    func resyncCatalog(restart: Bool) {
        let entries = catalogEntries()
        installQueue.async {
            guard AerialCatalog.isEnabled else { return }
            try? AerialCatalog.sync(entries)
            UserDefaults.standard.set(Date(), forKey: "catalogSyncedAppleList")
            if restart { AerialFiles.restartWallpaperAgent() }
        }
    }

    func wallpaperRemoved(_ id: UUID) {
        guard catalogEnabled else { return }
        let entries = catalogEntries().filter { $0.id != id }
        let wasSelected = aerialID == id.uuidString
        installQueue.async { [weak self] in
            try? AerialCatalog.sync(entries)
            if wasSelected { try? AerialCatalog.select(assetID: AerialCatalog.previousAppleAssetID()) }
            AerialFiles.restartWallpaperAgent()
            Task { @MainActor in self?.refresh() }
        }
    }

    func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "didMigrateToAerialCatalog") else { return }
        UserDefaults.standard.set(true, forKey: "didMigrateToAerialCatalog")
        let entries = catalogEntries()
        let selected = aerialID
        let owner = selected.flatMap { AerialFiles.getXattr(AerialCatalog.videoURL($0), AerialFiles.markerKey) }
            .flatMap { String(data: $0, encoding: .utf8) }
        installQueue.async { [weak self] in
            var changed = Self.restoreReplacedAppleVideos()
            if AerialCatalog.isEnabled {
                try? AerialCatalog.sync(entries)
                if let selected, let owner, owner != selected, entries.contains(where: { $0.id.uuidString == owner }) {
                    try? AerialCatalog.select(assetID: owner)
                }
                changed = true
            }
            if changed { AerialFiles.restartWallpaperAgent() }
            Task { @MainActor in self?.refresh() }
        }
    }

    func repairSelectionIfNeeded() {
        guard catalogEnabled, let selected = aerialID else { return }
        let known = AerialCatalog.appleAssetIDs().union(catalogEntries().map(\.id.uuidString))
        guard !known.contains(selected) else { return }
        installQueue.async { [weak self] in
            try? AerialCatalog.select(assetID: AerialCatalog.previousAppleAssetID())
            AerialFiles.restartWallpaperAgent()
            Task { @MainActor in self?.refresh() }
        }
    }

    nonisolated private static func restoreReplacedAppleVideos() -> Bool {
        let fm = FileManager.default
        var restored = false
        for id in AerialCatalog.appleAssetIDs() {
            let target = AerialFiles.videoURL(id)
            let backup = AerialFiles.backupURL(id)
            guard AerialFiles.getXattr(target, AerialFiles.markerKey) != nil, fm.fileExists(atPath: backup.path) else { continue }
            let tmp = target.deletingLastPathComponent().appendingPathComponent(".staylive.tmp")
            try? fm.removeItem(at: tmp)
            guard (try? fm.copyItem(at: backup, to: tmp)) != nil,
                  (try? fm.replaceItemAt(target, withItemAt: tmp)) != nil else { continue }
            removexattr(target.path, AerialFiles.markerKey, 0)
            restored = true
        }
        return restored
    }

    var hasBackup: Bool { aerialID.map { FileManager.default.fileExists(atPath: AerialFiles.backupURL($0).path) } ?? false }

    func queuePosition(_ id: UUID) -> Int? { queue.firstIndex(of: id).map { $0 + 1 } }

    // MARK: Time estimates

    private var measuredFPS: Double {
        get { let v = UserDefaults.standard.double(forKey: "encodeFPS"); return v > 0 ? v : 53 }
        set { UserDefaults.standard.set(newValue, forKey: "encodeFPS") }
    }

    func estimatedConversionSeconds(_ w: Wallpaper) -> Double {
        AerialEncoder.targetSeconds(forSourceDuration: w.duration) * Double(AerialEncoder.fps) / measuredFPS
    }

    func remainingSeconds(_ w: Wallpaper) -> Double {
        if convertingID == w.id {
            if progress > 0.03, let start = conversionStart {
                return Date().timeIntervalSince(start) / progress * (1 - progress)
            }
            return estimatedConversionSeconds(w) * (1 - progress)
        }
        guard let index = queue.firstIndex(of: w.id) else { return estimatedConversionSeconds(w) }
        var total = library.item(convertingID).map { remainingSeconds($0) } ?? 0
        for id in queue[...index] { total += library.item(id).map(estimatedConversionSeconds) ?? 0 }
        return total
    }

    static func durationText(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(max(s, 1)) sec" }
        let m = Int((seconds / 60).rounded())
        return m < 60 ? "\(m) min" : String(format: "%d h %d min", m / 60, m % 60)
    }

    // MARK: Actions

    func apply(_ w: Wallpaper) {
        refresh()
        if !AerialCatalog.isAvailable {
            guard let aerialID else { errorMessage = LockScreenError.noAerialSelected.localizedDescription; return }
            guard FileManager.default.fileExists(atPath: AerialFiles.videoURL(aerialID).path) else {
                errorMessage = LockScreenError.aerialNotDownloaded.localizedDescription; return
            }
        }
        requestedID = w.id
        if let cached = library.aerialURL(w), FileManager.default.fileExists(atPath: cached.path) {
            install(w.id, from: cached)
            return
        }
        if convertingID == w.id || queue.contains(w.id) { return }
        queue.append(w.id)
        ToastCenter.shared.show("Preparing \(w.name) for the lock screen",
                                message: "This takes about \(Self.durationText(remainingSeconds(w))). Keep using StayLive; you'll be told when it's set.",
                                symbol: "hourglass", style: .info)
        startNextConversion()
    }

    func cancel(_ id: UUID) {
        if requestedID == id { requestedID = nil }
        if convertingID == id { cancelToken.set(true) } else { queue.removeAll { $0 == id } }
    }

    private func startNextConversion() {
        guard convertingID == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let w = library.item(id) else { startNextConversion(); return }

        let token = CancelToken()
        cancelToken = token
        convertingID = id
        progress = 0
        conversionStart = Date()

        let source = library.videoURL(w)
        let outName = "\(id.uuidString)-aerial.mov"
        let outURL = AppPaths.aerials.appendingPathComponent(outName)
        let seconds = AerialEncoder.targetSeconds(forSourceDuration: w.duration)
        let frameCount = seconds * Double(AerialEncoder.fps)

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try AerialEncoder.encode(
                    source: source, to: outURL, seconds: seconds,
                    isCancelled: { token.get() },
                    progress: { p in Task { @MainActor in if self?.convertingID == id { self?.progress = p } } })
                await MainActor.run { self?.conversionFinished(id, outName: outName, outURL: outURL, frames: frameCount) }
            } catch {
                try? FileManager.default.removeItem(at: outURL)
                await MainActor.run { self?.conversionFailed(id, error: error) }
            }
        }
    }

    private func conversionFinished(_ id: UUID, outName: String, outURL: URL, frames: Double) {
        if let start = conversionStart { measuredFPS = frames / max(Date().timeIntervalSince(start), 1) }
        library.setAerial(outName, for: id)
        if catalogEnabled { resyncCatalog(restart: false) }
        convertingID = nil
        conversionStart = nil
        if requestedID == id {
            install(id, from: outURL)
        } else if let w = library.item(id) {
            ToastCenter.shared.show("\(w.name) is ready for the lock screen", message: "Apply it any time; it switches instantly.",
                                    symbol: "lock.fill", notify: true)
        }
        startNextConversion()
    }

    private func conversionFailed(_ id: UUID, error: Error) {
        if case .cancelled? = error as? AerialEncoderError {} else {
            errorMessage = error.localizedDescription
            ToastCenter.shared.show("Lock screen conversion failed", message: error.localizedDescription,
                                    symbol: "exclamationmark.triangle.fill", style: .error, notify: true)
        }
        if requestedID == id { requestedID = nil }
        convertingID = nil
        conversionStart = nil
        startNextConversion()
    }

    private func install(_ id: UUID, from url: URL) {
        installingID = id
        let entries = catalogEntries()
        let legacyTarget = aerialID
        installQueue.async { [weak self] in
            let result: Result<Bool, Error> = Result {
                if AerialCatalog.isAvailable {
                    try AerialCatalog.sync(entries)
                    UserDefaults.standard.set(Date(), forKey: "catalogSyncedAppleList")
                    try AerialCatalog.select(assetID: id.uuidString)
                    let start = Date()
                    AerialFiles.restartWallpaperAgent()
                    if AerialCatalog.overrideWasHonored(since: start) { return true }
                    AerialCatalog.disable()
                    let fallback = AerialCatalog.previousAppleAssetID()
                    try AerialCatalog.select(assetID: fallback)
                    try Self.install(aerial: url, wallpaperID: id, aerialID: fallback)
                    return false
                }
                guard let legacyTarget else { throw LockScreenError.noAerialSelected }
                try Self.install(aerial: url, wallpaperID: id, aerialID: legacyTarget)
                return false
            }
            Task { @MainActor in
                guard let self else { return }
                if self.installingID == id { self.installingID = nil }
                switch result {
                case .failure(let e):
                    self.errorMessage = e.localizedDescription
                case .success(let viaCatalog):
                    if let w = self.library.item(id) {
                        ToastCenter.shared.show("Lock screen set to \(w.name)",
                                                message: viaCatalog ? "Lock your Mac to see it. It's also under StayLive in System Settings → Wallpaper."
                                                                    : "Lock your Mac to see it.",
                                                symbol: "lock.fill", notify: true)
                    }
                }
                if self.requestedID == id { self.requestedID = nil }
                self.refresh()
            }
        }
    }

    nonisolated private static func install(aerial: URL, wallpaperID: UUID, aerialID: String) throws {
        let fm = FileManager.default
        let target = AerialFiles.videoURL(aerialID)
        let backup = AerialFiles.backupURL(aerialID)
        let isOurs = AerialFiles.getXattr(target, AerialFiles.markerKey) != nil
        if !isOurs && !fm.fileExists(atPath: backup.path) {
            try fm.copyItem(at: target, to: backup)
        }
        guard let sourceURL = AerialFiles.getXattr(target, "SourceURL"),
              let etag = AerialFiles.getXattr(target, "LastETag") else {
            throw LockScreenError.installFailed("Apple's download info is missing on the current Aerial file.")
        }
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".staylive.tmp")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: aerial, to: tmp)
        guard AerialFiles.setXattr(tmp, "SourceURL", sourceURL),
              AerialFiles.setXattr(tmp, "LastETag", etag),
              AerialFiles.setXattr(tmp, AerialFiles.markerKey, Data(wallpaperID.uuidString.utf8)) else {
            try? fm.removeItem(at: tmp)
            throw LockScreenError.installFailed("Couldn't copy Apple's download info onto the new video.")
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        _ = try fm.replaceItemAt(target, withItemAt: tmp)
        AerialFiles.restartWallpaperAgent()
    }

    func restoreOriginal() {
        guard installingID == nil else { return }
        requestedID = nil
        let selected = aerialID
        let ours = Set(catalogEntries().map(\.id.uuidString))
        installQueue.async { [weak self] in
            if AerialCatalog.isEnabled {
                AerialCatalog.disable()
                if let selected, ours.contains(selected) || !AerialCatalog.appleAssetIDs().contains(selected) {
                    try? AerialCatalog.select(assetID: AerialCatalog.previousAppleAssetID())
                }
            }
            _ = Self.restoreReplacedAppleVideos()
            AerialFiles.restartWallpaperAgent()
            Task { @MainActor in
                self?.refresh()
                ToastCenter.shared.show("Lock screen is back to Apple's Aerials", symbol: "arrow.uturn.backward.circle.fill", style: .info)
            }
        }
    }
}
