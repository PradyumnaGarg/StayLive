import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CatalogEntry: Sendable {
    let id: UUID
    let name: String
    let video: URL
    let thumbnail: URL?
}

enum AerialCatalog {
    static let categoryID = "054687DD-553F-465C-8E6F-442620FDE9F6"
    static let subcategoryID = "BE2B4D43-BA49-4008-A9F1-A76D05DDAB40"
    static let defaultAppleAssetID = "4207734D-74FE-4F92-B5E1-6EC8DEE24A15"
    static let suite = "com.apple.wallpaper.aerial"
    static let forceLocalKey = "AerialManifestForceLocal"
    static let overrideKey = "AerialManifestLocalPathOverride"
    static let previousSelectionKey = "previousAppleAerialID"

    static var aerials: URL { AerialFiles.wallpaperRoot.appendingPathComponent("aerials") }
    static var appleManifest: URL { aerials.appendingPathComponent("manifest/entries.json") }
    static var ourManifest: URL { aerials.appendingPathComponent("manifest/staylive-entries.json") }
    static var indexPlist: URL { AerialFiles.wallpaperRoot.appendingPathComponent("Store/Index.plist") }
    static func videoURL(_ id: String) -> URL { aerials.appendingPathComponent("videos/\(id).mov") }
    static func thumbnailURL(_ id: String) -> URL { aerials.appendingPathComponent("thumbnails/\(id).png") }
    static func sourceURL(_ id: String) -> String { "https://staylive.local/aerials/\(id).mov" }

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: appleManifest.path) }

    static var isEnabled: Bool {
        let d = UserDefaults(suiteName: suite)
        return d?.bool(forKey: forceLocalKey) == true && d?.string(forKey: overrideKey) == ourManifest.path
    }

    static func appleAssetIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: appleManifest),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else { return [] }
        return Set(assets.compactMap { $0["id"] as? String })
    }

    static func sync(_ entries: [CatalogEntry]) throws {
        let fm = FileManager.default
        guard let base = try JSONSerialization.jsonObject(with: Data(contentsOf: appleManifest)) as? [String: Any] else {
            throw LockScreenError.installFailed("macOS's Aerial list couldn't be read.")
        }
        var json = base
        var categories = (json["categories"] as? [[String: Any]] ?? []).filter { $0["id"] as? String != categoryID }
        var assets = (json["assets"] as? [[String: Any]] ?? []).filter { !(($0["categories"] as? [String])?.contains(categoryID) ?? false) }
        let appleIDs = Set(assets.compactMap { $0["id"] as? String })

        if let first = entries.first {
            categories.insert([
                "id": categoryID,
                "localizedNameKey": "StayLive",
                "localizedDescriptionKey": "Your StayLive wallpapers",
                "preferredOrder": -1,
                "previewImage": "https://staylive.local/thumbnails/\(categoryID).png",
                "representativeAssetID": first.id.uuidString,
                "subcategories": [[
                    "id": subcategoryID,
                    "localizedNameKey": "StayLive",
                    "localizedDescriptionKey": "Your StayLive wallpapers",
                    "preferredOrder": 0,
                    "previewImage": "https://staylive.local/thumbnails/\(subcategoryID).png",
                    "representativeAssetID": first.id.uuidString,
                    "combineVariants": false,
                ]],
            ], at: 0)
            for (index, entry) in entries.enumerated() {
                let id = entry.id.uuidString
                assets.insert([
                    "id": id,
                    "accessibilityLabel": entry.name,
                    "localizedNameKey": entry.name,
                    "categories": [categoryID],
                    "subcategories": [subcategoryID],
                    "includeInShuffle": true,
                    "showInTopLevel": true,
                    "pointsOfInterest": [String: String](),
                    "preferredOrder": index,
                    "previewImage": "https://staylive.local/thumbnails/\(id).png",
                    "shotID": "STAYLIVE_\(id.prefix(8))",
                    "url-4K-SDR-240FPS": sourceURL(id),
                ], at: index)
            }
        }
        json["categories"] = categories
        json["assets"] = assets

        for entry in entries {
            let id = entry.id.uuidString
            let dest = videoURL(id)
            let sourceSize = (try? fm.attributesOfItem(atPath: entry.video.path)[.size] as? Int) ?? -1
            let destSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -2
            if sourceSize != destSize {
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: entry.video, to: dest)
            }
            _ = AerialFiles.setXattr(dest, "SourceURL", Data(sourceURL(id).utf8))
            _ = AerialFiles.setXattr(dest, "LastETag", Data("\"staylive-\(id)\"".utf8))
            _ = AerialFiles.setXattr(dest, AerialFiles.markerKey, Data(id.utf8))
            if let thumbnail = entry.thumbnail { writePNG(from: thumbnail, to: thumbnailURL(id)) }
        }
        if let thumbnail = entries.first?.thumbnail {
            writePNG(from: thumbnail, to: thumbnailURL(categoryID))
            writePNG(from: thumbnail, to: thumbnailURL(subcategoryID))
        }

        let keep = Set(entries.map(\.id.uuidString))
        let videosDir = aerials.appendingPathComponent("videos")
        for file in (try? fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)) ?? [] {
            let id = file.deletingPathExtension().lastPathComponent
            guard file.pathExtension == "mov", !appleIDs.contains(id), !keep.contains(id),
                  AerialFiles.getXattr(file, AerialFiles.markerKey) != nil else { continue }
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: thumbnailURL(id))
        }

        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: ourManifest, options: .atomic)

        let defaults = UserDefaults(suiteName: suite)
        defaults?.set(true, forKey: forceLocalKey)
        defaults?.set(ourManifest.path, forKey: overrideKey)
        CFPreferencesAppSynchronize(suite as CFString)
    }

    static func disable() {
        let fm = FileManager.default
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removeObject(forKey: forceLocalKey)
        defaults?.removeObject(forKey: overrideKey)
        CFPreferencesAppSynchronize(suite as CFString)
        let appleIDs = appleAssetIDs()
        let videosDir = aerials.appendingPathComponent("videos")
        for file in (try? fm.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)) ?? [] {
            let id = file.deletingPathExtension().lastPathComponent
            guard !appleIDs.contains(id), AerialFiles.getXattr(file, AerialFiles.markerKey) != nil else { continue }
            try? fm.removeItem(at: file)
            try? fm.removeItem(at: thumbnailURL(id))
        }
        try? fm.removeItem(at: thumbnailURL(categoryID))
        try? fm.removeItem(at: thumbnailURL(subcategoryID))
        try? fm.removeItem(at: ourManifest)
    }

    static func selectedDesktopAssetID() -> String? {
        guard let root = readIndex(),
              let choice = desktopChoice(in: root["AllSpacesAndDisplays"] as? [String: Any]),
              (choice["Provider"] as? String) == "com.apple.wallpaper.choice.aerials",
              let config = choice["Configuration"] as? Data,
              let dict = try? PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any] else { return nil }
        return dict["assetID"] as? String
    }

    static func select(assetID: String) throws {
        guard var root = readIndex() else { throw LockScreenError.installFailed("macOS's wallpaper settings couldn't be read.") }
        if let current = selectedDesktopAssetID(), appleAssetIDs().contains(current) {
            UserDefaults.standard.set(current, forKey: previousSelectionKey)
        }
        let config = try PropertyListSerialization.data(fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
        let choice: [String: Any] = ["Configuration": config, "Files": [Any](), "Provider": "com.apple.wallpaper.choice.aerials"]

        func update(_ scope: inout [String: Any]) {
            guard var desktop = scope["Desktop"] as? [String: Any] else { return }
            var content = desktop["Content"] as? [String: Any] ?? [:]
            let wasAerial = ((content["Choices"] as? [[String: Any]])?.first?["Provider"] as? String) == "com.apple.wallpaper.choice.aerials"
            content["Choices"] = [choice]
            if !wasAerial { content.removeValue(forKey: "EncodedOptionValues") }
            desktop["Content"] = content
            desktop["LastSet"] = Date()
            scope["Desktop"] = desktop
        }

        if var all = root["AllSpacesAndDisplays"] as? [String: Any] {
            update(&all)
            root["AllSpacesAndDisplays"] = all
        }
        for key in ["Displays", "Spaces"] {
            guard var group = root[key] as? [String: Any] else { continue }
            for (name, value) in group {
                guard var scope = value as? [String: Any] else { continue }
                update(&scope)
                group[name] = scope
            }
            root[key] = group
        }
        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try data.write(to: indexPlist, options: .atomic)
    }

    static func previousAppleAssetID() -> String {
        let saved = UserDefaults.standard.string(forKey: previousSelectionKey)
        if let saved, appleAssetIDs().contains(saved) { return saved }
        return defaultAppleAssetID
    }

    static func overrideWasHonored(since start: Date, timeout: TimeInterval = 10) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 1.5)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            p.arguments = ["show", "--start", formatter.string(from: start.addingTimeInterval(-1)), "--style", "compact",
                           "--predicate", "process == \"WallpaperAerialsExtension\" AND eventMessage CONTAINS \"AerialManifestLocalPathOverride is set\""]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            if output.contains("staylive-entries.json") { return true }
        }
        return false
    }

    private static func readIndex() -> [String: Any]? {
        guard let data = try? Data(contentsOf: indexPlist) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    private static func desktopChoice(in scope: [String: Any]?) -> [String: Any]? {
        (((scope?["Desktop"] as? [String: Any])?["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first
    }

    private static func writePNG(from source: URL, to destination: URL) {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
