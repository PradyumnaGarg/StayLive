import AppKit
import AVFoundation
import SwiftUI

struct Wallpaper: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var fileName: String
    var duration: Double
    var width: Int
    var height: Int
    var fps: Double
    var addedAt: Date
    var aerialFileName: String?
    var hasAudio: Bool?
    var builtInKey: String?

    var isBuiltIn: Bool { builtInKey != nil }

    var resolutionLabel: String {
        switch height {
        case 2160...: return "4K"
        case 1440..<2160: return "1440p"
        case 1080..<1440: return "1080p"
        case 720..<1080: return "720p"
        default: return "\(width)×\(height)"
        }
    }

    var durationLabel: String {
        let s = Int(duration.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

enum AppPaths {
    static let root: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StayLive", isDirectory: true)
        for sub in ["Videos", "Thumbnails", "Aerials", "Backups"] {
            try? FileManager.default.createDirectory(at: url.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return url
    }()
    static let videos = root.appendingPathComponent("Videos")
    static let thumbnails = root.appendingPathComponent("Thumbnails")
    static let aerials = root.appendingPathComponent("Aerials")
    static let backups = root.appendingPathComponent("Backups")
    static let libraryFile = root.appendingPathComponent("library.json")
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [Wallpaper] = []
    @Published var isImporting = false
    private var thumbnailCache: [UUID: NSImage] = [:]

    private init() {
        if let data = try? Data(contentsOf: AppPaths.libraryFile),
           let decoded = try? JSONDecoder().decode([Wallpaper].self, from: data) {
            items = decoded.filter { FileManager.default.fileExists(atPath: videoURL($0).path) }
        }
        Task { await fillMissingAudioFlags() }
    }

    func videoURL(_ w: Wallpaper) -> URL { AppPaths.videos.appendingPathComponent(w.fileName) }
    func thumbnailURL(_ w: Wallpaper) -> URL { AppPaths.thumbnails.appendingPathComponent("\(w.id.uuidString).jpg") }
    func aerialURL(_ w: Wallpaper) -> URL? { w.aerialFileName.map { AppPaths.aerials.appendingPathComponent($0) } }
    func item(_ id: UUID?) -> Wallpaper? { items.first { $0.id == id } }

    var featured: [Wallpaper] {
        let builtIns = items.filter(\.isBuiltIn)
        let recent = items.filter { !$0.isBuiltIn }.sorted { $0.addedAt > $1.addedAt }.prefix(5)
        return Array(recent) + builtIns
    }

    func addGenerated(id: UUID, url: URL, name: String, builtInKey: String) async {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 20
        let w = Wallpaper(id: id, name: name, fileName: url.lastPathComponent, duration: duration,
                          width: BuiltInRenderer.width, height: BuiltInRenderer.height, fps: Double(BuiltInRenderer.fps),
                          addedAt: Date(), aerialFileName: nil, hasAudio: false, builtInKey: builtInKey)
        await makeThumbnail(asset: asset, duration: duration, to: thumbnailURL(w))
        items.append(w)
        save()
    }

    func thumbnail(_ w: Wallpaper) -> NSImage? {
        if let cached = thumbnailCache[w.id] { return cached }
        let image = NSImage(contentsOf: thumbnailURL(w))
        thumbnailCache[w.id] = image
        return image
    }

    func setAerial(_ fileName: String, for id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].aerialFileName = fileName
        save()
    }

    func rename(_ w: Wallpaper, to name: String) {
        guard let i = items.firstIndex(where: { $0.id == w.id }), !name.isEmpty else { return }
        items[i].name = name
        save()
    }

    func remove(_ w: Wallpaper) {
        try? FileManager.default.removeItem(at: videoURL(w))
        try? FileManager.default.removeItem(at: thumbnailURL(w))
        if let a = aerialURL(w) { try? FileManager.default.removeItem(at: a) }
        thumbnailCache[w.id] = nil
        items.removeAll { $0.id == w.id }
        save()
        if DesktopController.shared.currentID == w.id { DesktopController.shared.setWallpaper(nil) }
    }

    @discardableResult
    func importVideos(_ urls: [URL]) async -> [Wallpaper] {
        isImporting = true
        defer { isImporting = false }
        var added: [Wallpaper] = []
        for url in urls {
            if let w = try? await importVideo(url) { added.append(w) }
        }
        return added
    }

    private func importVideo(_ source: URL) async throws -> Wallpaper {
        let id = UUID()
        let fileName = "\(id.uuidString).\(source.pathExtension.isEmpty ? "mov" : source.pathExtension)"
        let dest = AppPaths.videos.appendingPathComponent(fileName)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.copyItem(at: source, to: dest)

        let asset = AVURLAsset(url: dest)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            try? FileManager.default.removeItem(at: dest)
            throw CocoaError(.fileReadCorruptFile)
        }
        let (size, fps, transform) = try await track.load(.naturalSize, .nominalFrameRate, .preferredTransform)
        let duration = try await asset.load(.duration).seconds
        let oriented = size.applying(transform)

        let w = Wallpaper(id: id, name: source.deletingPathExtension().lastPathComponent, fileName: fileName,
                          duration: duration, width: Int(abs(oriented.width)), height: Int(abs(oriented.height)),
                          fps: Double(fps), addedAt: Date(), aerialFileName: nil,
                          hasAudio: !(try await asset.loadTracks(withMediaType: .audio)).isEmpty)
        await makeThumbnail(asset: asset, duration: duration, to: thumbnailURL(w))
        items.insert(w, at: 0)
        save()
        return w
    }

    private func makeThumbnail(asset: AVAsset, duration: Double, to url: URL) async {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 540)
        let time = CMTime(seconds: min(1, duration / 3), preferredTimescale: 600)
        guard let cg = try? await generator.image(at: time).image else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.write(to: url)
    }

    private func fillMissingAudioFlags() async {
        var changed = false
        for (i, w) in items.enumerated() where w.hasAudio == nil {
            let tracks = (try? await AVURLAsset(url: videoURL(w)).loadTracks(withMediaType: .audio)) ?? []
            items[i].hasAudio = !tracks.isEmpty
            changed = true
        }
        if changed { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: AppPaths.libraryFile, options: .atomic) }
    }
}
