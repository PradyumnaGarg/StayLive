import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

final class LoopingPlayerNSView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private let playerLayer = AVPlayerLayer()
    private(set) var url: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func play(_ newURL: URL?) {
        guard newURL != url else { return }
        url = newURL
        player.pause()
        looper = nil
        player.removeAllItems()
        guard let newURL else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: newURL))
        player.play()
    }

    func stop() { player.pause(); looper = nil; player.removeAllItems(); url = nil }

    func setMuted(_ muted: Bool) { player.isMuted = muted }

    func setPaused(_ paused: Bool) {
        guard url != nil else { return }
        if paused, player.rate != 0 { player.pause() }
        if !paused, player.rate == 0 { player.play() }
    }
}

struct LoopingPlayer: NSViewRepresentable {
    let url: URL?
    var muted = true
    var paused = false
    func makeNSView(context: Context) -> LoopingPlayerNSView { LoopingPlayerNSView() }
    func updateNSView(_ view: LoopingPlayerNSView, context: Context) { view.setMuted(muted); view.play(url); view.setPaused(paused) }
    static func dismantleNSView(_ view: LoopingPlayerNSView, coordinator: ()) { view.stop() }
}

struct HoverPreview: View {
    @EnvironmentObject private var library: LibraryStore
    let wallpaper: Wallpaper
    var playing: Bool = false
    @State private var hovering = false
    @State private var previewing = false

    var body: some View {
        ZStack {
            if let image = library.thumbnail(wallpaper) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Theme.panel
            }
            if previewing || playing {
                LoopingPlayer(url: library.videoURL(wallpaper))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onHover { inside in
            hovering = inside
            if inside {
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if hovering { withAnimation(.easeIn(duration: 0.2)) { previewing = true } }
                }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { previewing = false }
            }
        }
    }
}

struct Badge: View {
    let text: String
    let symbol: String
    var compact = false
    var body: some View {
        Group {
            if compact {
                Image(systemName: symbol)
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
                    .help(text)
            } else {
                Label(text, systemImage: symbol)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .font(.caption2.weight(.semibold))
    }
}

struct WallpaperCard: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    let wallpaper: Wallpaper
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HoverPreview(wallpaper: wallpaper)

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.name).font(.headline).lineLimit(1)
                    Text("\(wallpaper.resolutionLabel) · \(wallpaper.durationLabel)")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                if lockScreen.convertingID == wallpaper.id {
                    GradientRing(value: lockScreen.progress)
                } else if lockScreen.queuePosition(wallpaper.id) != nil {
                    Image(systemName: "clock").font(.callout).foregroundStyle(.white.opacity(0.8)).help("Queued for conversion")
                }
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                if desktop.currentID == wallpaper.id { Badge(text: "Desktop", symbol: "desktopcomputer", compact: true) }
                if lockScreen.installedID == wallpaper.id { Badge(text: "Lock Screen", symbol: "lock.fill", compact: true) }
                if screenSaver.currentID == wallpaper.id { Badge(text: "Screen Saver", symbol: "sparkles.tv", compact: true) }
            }
            .padding(10)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.cardStroke), lineWidth: isSelected ? 3 : 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.35 : 0.18), radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
        .scaleEffect(hovering ? 1.025 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }
}

enum AppSection: String, Hashable, CaseIterable {
    case home, library

    var title: String {
        switch self {
        case .home: return "Home"
        case .library: return "Library"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .library: return "square.grid.2x2.fill"
        }
    }
}

struct NavigationPill: View {
    @Binding var selection: AppSection
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { selection = section }
                } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .foregroundStyle(selection == section ? Color.white : Color.primary)
                        .background {
                            if selection == section {
                                Capsule().fill(Color.accentColor)
                                    .matchedGeometryEffect(id: "pill", in: highlight)
                                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6, y: 2)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

enum LibraryFilter: String, CaseIterable {
    case all = "All", builtIn = "Built-in", mine = "My Videos"
}

@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()
    @Published var section: AppSection = .home {
        didSet { if section != .library { showDetails = false } }
    }
    @Published var selectedID: UUID?
    @Published var showDetails = false
    @Published var showSettings = false
    @Published var filter: LibraryFilter = .all

    func open(_ w: Wallpaper) {
        section = .library
        selectedID = w.id
        showDetails = true
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @EnvironmentObject private var nav: AppNavigation
    @State private var importing = false
    @State private var dropTargeted = false

    var body: some View {
        Group {
            switch nav.section {
            case .home: HomeView(importing: $importing)
            case .library: LibraryPage(importing: $importing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AmbientBackground(image: library.item(desktop.currentID).flatMap { library.thumbnail($0) }))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationPill(selection: $nav.section)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { importing = true } label: { Label("Add Videos", systemImage: "plus") }
                    .help("Add videos to your library")
                Button { nav.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .help("Settings")
            }
        }
        .sheet(isPresented: $nav.showSettings) {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings").font(.title2.bold())
                    Spacer()
                    Button("Done") { nav.showSettings = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding([.horizontal, .top], 20)
                SettingsView()
            }
            .frame(width: 560, height: 620)
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(Label("Drop to add to your library", systemImage: "square.and.arrow.down").font(.title2.bold()))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let videos = urls.filter { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .movie) ?? false }
            guard !videos.isEmpty else { return false }
            add(videos)
            return true
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            add(urls)
        }
        .alert("Screen Saver", isPresented: Binding(
            get: { screenSaver.errorMessage != nil },
            set: { if !$0 { screenSaver.errorMessage = nil } })
        ) {
            Button("OK") { screenSaver.errorMessage = nil }
        } message: {
            Text(screenSaver.errorMessage ?? "")
        }
        .alert("Lock Screen", isPresented: Binding(
            get: { lockScreen.errorMessage != nil },
            set: { if !$0 { lockScreen.errorMessage = nil } })
        ) {
            Button("OK") { lockScreen.errorMessage = nil }
        } message: {
            Text(lockScreen.errorMessage ?? "")
        }
        .onAppear { lockScreen.refresh() }
    }

    private func add(_ urls: [URL]) {
        Task {
            if let first = await library.importVideos(urls).first {
                nav.section = .library
                nav.open(first)
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var builtIns: BuiltInLibrary
    @EnvironmentObject private var nav: AppNavigation
    @Binding var importing: Bool

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if library.featured.isEmpty {
                        Color.clear.frame(height: 60)
                    } else {
                        FeaturedHero(items: library.featured)
                            .frame(height: max(380, geo.size.height * 2 / 3 + geo.safeAreaInsets.top))
                    }

                    VStack(alignment: .leading, spacing: 22) {
                        if let style = builtIns.currentStyle {
                            HStack(spacing: 12) {
                                GradientRing(value: builtIns.progress)
                                Text("Preparing built-in wallpaper “\(style.name)”…").font(.callout)
                                Spacer()
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        HStack(alignment: .firstTextBaseline) {
                            SectionHeader(title: "Now Showing")
                            Spacer()
                            Button { importing = true } label: { Label("Add Videos", systemImage: "plus") }
                                .buttonStyle(GlassButtonStyle())
                                .fixedSize()
                            Button { nav.section = .library } label: { Label("Browse Library", systemImage: "square.grid.2x2") }
                                .buttonStyle(GlassButtonStyle())
                                .fixedSize()
                        }
                        NowShowing()
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

struct FeaturedHero: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var nav: AppNavigation
    @Environment(\.controlActiveState) private var activeState
    let items: [Wallpaper]
    @State private var index = 0
    @State private var soundOn = false

    private var current: Wallpaper? { items.isEmpty ? nil : items[min(index, items.count - 1)] }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let current {
                ZStack {
                    if let image = library.thumbnail(current) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    }
                    LoopingPlayer(url: library.videoURL(current), muted: !soundOn || activeState == .inactive,
                                  paused: activeState == .inactive)
                }
                .id(current.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }

            LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                   .init(color: .clear, location: 0.22),
                                   .init(color: .clear, location: 0.5),
                                   .init(color: .black.opacity(0.75), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

            if let current {
                HStack(alignment: .bottom, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.isBuiltIn ? "FEATURED · BUILT-IN" : "FEATURED")
                            .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                        Text(current.name)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text("\(current.resolutionLabel) · \(current.durationLabel)\(current.hasAudio == true ? " · Sound" : "")")
                            .font(.callout).foregroundStyle(.white.opacity(0.75))
                        Button { nav.open(current) } label: {
                            Label("Apply", systemImage: "sparkles")
                        }
                        .buttonStyle(GradientButtonStyle())
                        .fixedSize()
                        .padding(.top, 6)
                        .help("Choose where to use this wallpaper")
                    }
                    Spacer()
                    controls(for: current)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.bottom, 30)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: current?.id)
        .clipped()
    }

    private func controls(for w: Wallpaper) -> some View {
        HStack(spacing: 6) {
            heroButton("chevron.left", "Previous") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\(min(index, items.count - 1) + 1) / \(items.count)")
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(minWidth: 52)
            heroButton("chevron.right", "Next") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Divider().frame(height: 22).overlay(.white.opacity(0.3)).padding(.horizontal, 4)
            heroButton(soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", soundOn ? "Mute" : "Play sound") {
                soundOn.toggle()
            }
            .disabled(w.hasAudio != true)
            .opacity(w.hasAudio == true ? 1 : 0.4)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
    }

    private func heroButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func step(_ offset: Int) {
        guard !items.isEmpty else { return }
        index = (min(index, items.count - 1) + offset + items.count) % items.count
    }
}

struct NowShowing: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @EnvironmentObject private var nav: AppNavigation

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            slot(title: "Desktop", symbol: "desktopcomputer", wallpaper: library.item(desktop.currentID),
                 fallback: "Nothing playing",
                 detail: desktop.currentID == nil ? nil : (desktop.isPlaying ? "Playing" : (desktop.isUserPaused ? "Paused" : "Idle"))) {
                if desktop.currentID != nil {
                    Button { desktop.togglePause() } label: {
                        Image(systemName: desktop.isUserPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(desktop.isUserPaused ? "Resume" : "Pause")
                }
            }
            slot(title: "Lock Screen", symbol: "lock.fill", wallpaper: library.item(lockScreen.installedID),
                 fallback: lockScreen.aerialName.map { "Apple \($0)" } ?? "Apple default",
                 detail: lockScreen.convertingID.flatMap { library.item($0) }.map { "Converting \($0.name)… \(Int(lockScreen.progress * 100))%" }) { EmptyView() }
            slot(title: "Screen Saver", symbol: "sparkles.tv", wallpaper: library.item(screenSaver.currentID),
                 fallback: "Not set", detail: nil) { EmptyView() }
        }
    }

    private func slot<Accessory: View>(title: String, symbol: String, wallpaper: Wallpaper?, fallback: String, detail: String?,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let wallpaper {
                    HoverPreview(wallpaper: wallpaper)
                } else {
                    Theme.panel.overlay(Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
            .onTapGesture { if let wallpaper { nav.open(wallpaper) } else { nav.section = .library } }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
                    Text(wallpaper?.name ?? fallback).font(.callout.weight(.semibold)).lineLimit(1)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
                accessory()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
        .frame(maxWidth: .infinity)
    }
}

struct LibraryPage: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @EnvironmentObject private var nav: AppNavigation
    @Binding var importing: Bool

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 18)]

    private var visible: [Wallpaper] {
        switch nav.filter {
        case .all: return library.items
        case .builtIn: return library.items.filter(\.isBuiltIn)
        case .mine: return library.items.filter { !$0.isBuiltIn }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    SectionHeader(title: "Library", subtitle: "\(library.items.count) wallpapers")
                    Spacer()
                    if library.isImporting { ProgressView().controlSize(.small) }
                    Picker("", selection: $nav.filter) {
                        ForEach(LibraryFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                if visible.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visible) { w in
                            WallpaperCard(wallpaper: w, isSelected: nav.selectedID == w.id && nav.showDetails)
                                .onTapGesture { nav.open(w) }
                                .contextMenu { WallpaperContextMenu(wallpaper: w) }
                        }
                    }
                }
            }
            .padding(28)
        }
        .inspector(isPresented: $nav.showDetails) {
            if nav.showDetails, let w = library.item(nav.selectedID) {
                InspectorView(wallpaper: w)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            } else {
                ContentUnavailableView("No Selection", systemImage: "photo.on.rectangle",
                                       description: Text("Select a wallpaper to see details."))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(nav.filter == .mine ? "No videos of your own yet" : "Your library is empty").font(.title3.bold())
            Text("Drag videos here or click Add Videos.").foregroundStyle(.secondary)
            Button("Add Videos…") { importing = true }.buttonStyle(GradientButtonStyle()).fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [8, 6])))
    }
}

struct WallpaperContextMenu: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @EnvironmentObject private var nav: AppNavigation
    let wallpaper: Wallpaper

    var body: some View {
        Button("Set as Desktop") { desktop.setWallpaper(wallpaper.id) }
        Button("Set as Lock Screen") { lockScreen.apply(wallpaper) }
        Button("Set as Screen Saver") { screenSaver.set(wallpaper) }
        Button("Use Everywhere") { desktop.setWallpaper(wallpaper.id); lockScreen.apply(wallpaper); screenSaver.set(wallpaper) }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.videoURL(wallpaper)]) }
        Button("Remove from Library", role: .destructive) {
            if nav.selectedID == wallpaper.id { nav.showDetails = false; nav.selectedID = nil }
            library.remove(wallpaper)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @EnvironmentObject private var nav: AppNavigation
    let wallpaper: Wallpaper
    @State private var name = ""
    @State private var previewMuted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Details").font(.headline).foregroundStyle(.secondary)
                    Spacer()
                    Button { AppNavigation.shared.showDetails = false } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 26, height: 26)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Close details")
                }
                LoopingPlayer(url: nav.showDetails ? library.videoURL(wallpaper) : nil, muted: previewMuted || !nav.showDetails)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if wallpaper.hasAudio == true {
                            Button { previewMuted.toggle() } label: {
                                Image(systemName: previewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .frame(width: 30, height: 30)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                            .help(previewMuted ? "Play sound" : "Mute")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 5)

                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.title2.bold())
                    .onSubmit { library.rename(wallpaper, to: name) }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    infoRow("Resolution", "\(wallpaper.width) × \(wallpaper.height)")
                    infoRow("Frame rate", String(format: "%.0f fps", wallpaper.fps))
                    infoRow("Length", wallpaper.durationLabel)
                    infoRow("Sound", wallpaper.hasAudio == true ? "Yes" : "No audio track")
                    infoRow("Lock screen", wallpaper.aerialFileName == nil
                            ? "Needs conversion (~\(LockScreenController.durationText(lockScreen.estimatedConversionSeconds(wallpaper))))"
                            : "Converted, ready")
                }
                .font(.callout)

                Divider()

                VStack(spacing: 10) {
                    Button { desktop.setWallpaper(wallpaper.id); lockScreen.apply(wallpaper); screenSaver.set(wallpaper) } label: {
                        Label("Use Everywhere", systemImage: "sparkles").frame(maxWidth: .infinity)
                    }
                    .help("Desktop, lock screen and screen saver")
                    .buttonStyle(GradientButtonStyle())

                    HStack(spacing: 10) {
                        Button { desktop.setWallpaper(wallpaper.id) } label: {
                            Label("Desktop", systemImage: "desktopcomputer").frame(maxWidth: .infinity)
                        }
                        Button { lockScreen.apply(wallpaper) } label: {
                            Label(isOnLockScreen ? "On Lock Screen" : "Lock Screen",
                                  systemImage: isOnLockScreen ? "checkmark" : "lock").frame(maxWidth: .infinity)
                        }
                        .disabled(isOnLockScreen)
                    }
                    .buttonStyle(GlassButtonStyle())

                    Button { screenSaver.set(wallpaper) } label: {
                        Label(screenSaver.currentID == wallpaper.id ? "Screen Saver ✓" : "Screen Saver",
                              systemImage: "sparkles.tv").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                lockScreenStatus

                Text(lockScreenNote).font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .background(Theme.panel.opacity(0.85).ignoresSafeArea())
        .onAppear { name = wallpaper.name }
        .onChange(of: wallpaper.id) { name = wallpaper.name; previewMuted = false }
    }

    private var isOnLockScreen: Bool {
        lockScreen.installedID == wallpaper.id && lockScreen.installingID == nil && lockScreen.requestedID == nil
    }

    @ViewBuilder
    private var lockScreenStatus: some View {
        let id = wallpaper.id
        if lockScreen.convertingID == id {
            statusBox {
                HStack {
                    Text("Converting for lock screen…").font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int(lockScreen.progress * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                GradientProgressBar(value: lockScreen.progress)
                HStack {
                    Text("About \(LockScreenController.durationText(lockScreen.remainingSeconds(wallpaper))) left")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { lockScreen.cancel(id) }.controlSize(.small)
                }
                pendingNote
            }
        } else if let position = lockScreen.queuePosition(id) {
            statusBox {
                HStack {
                    Label("Queued for conversion", systemImage: "clock").font(.callout.weight(.medium))
                    Spacer()
                    Text(position == 1 ? "Next" : "#\(position) in queue").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Ready in about \(LockScreenController.durationText(lockScreen.remainingSeconds(wallpaper)))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { lockScreen.cancel(id) }.controlSize(.small)
                }
                pendingNote
            }
        } else if lockScreen.installingID == id {
            HStack { ProgressView().controlSize(.small); Text("Installing on lock screen…") }
        }
    }

    @ViewBuilder
    private var pendingNote: some View {
        if lockScreen.requestedID == wallpaper.id {
            Text("Will be set as your lock screen when ready.").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Will be saved for later. Your lock screen won't change.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func statusBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private var lockScreenNote: String {
        let aerial = lockScreen.aerialName.map { "Apple's \($0) Aerial" } ?? "the selected Aerial"
        return "The lock screen replaces \(aerial). Conversion to 4K · 240 fps runs once; after that applying it is instant."
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let current = library.item(desktop.currentID) {
                ZStack(alignment: .bottomLeading) {
                    HoverPreview(wallpaper: current)
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    HStack {
                        Text(current.name).font(.headline).lineLimit(1)
                        Spacer()
                        Button { desktop.togglePause() } label: {
                            Image(systemName: desktop.isUserPaused ? "play.fill" : "pause.fill")
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text("No desktop wallpaper yet").font(.headline)
            }

            if library.items.count > 1 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(library.items.prefix(6)) { w in
                        Button { desktop.setWallpaper(w.id) } label: {
                            Group {
                                if let image = library.thumbnail(w) {
                                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                                } else { Rectangle().fill(.quaternary) }
                            }
                            .frame(height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(desktop.currentID == w.id ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.clear), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(w.name)
                    }
                }
            }

            if let w = library.item(lockScreen.convertingID) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Converting \(w.name)… \(Int(lockScreen.progress * 100))%").lineLimit(1)
                        Spacer()
                        Text("~\(LockScreenController.durationText(lockScreen.remainingSeconds(w))) left").foregroundStyle(.secondary)
                    }
                    .font(.caption).monospacedDigit()
                    GradientProgressBar(value: lockScreen.progress)
                    if !lockScreen.queue.isEmpty {
                        Text("\(lockScreen.queue.count) more queued").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if library.item(desktop.currentID)?.hasAudio == true {
                HStack(spacing: 8) {
                    Button { desktop.soundEnabled.toggle() } label: {
                        Image(systemName: desktop.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 20)
                    }
                    .buttonStyle(.borderless)
                    .help(desktop.soundEnabled ? "Mute" : "Play sound")
                    Slider(value: $desktop.volume, in: 0...1).disabled(!desktop.soundEnabled)
                }
            }

            Divider()

            HStack {
                Button("Open StayLive") {
                    AppNavigation.shared.section = .home
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button {
                    AppNavigation.shared.showSettings = true
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                } label: { Image(systemName: "gearshape") }
                .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
        .background(AmbientBackground(image: library.item(desktop.currentID).flatMap { library.thumbnail($0) }))
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $desktop.launchAtLogin)
                if let error = desktop.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Pause on battery power", isOn: $desktop.pauseOnBattery)
            }
            Section("Desktop Sound") {
                Toggle("Play wallpaper sound", isOn: $desktop.soundEnabled)
                Slider(value: $desktop.volume, in: 0...1) { Text("Volume") }.disabled(!desktop.soundEnabled)
                Text("Plays from your main display only, and only while the desktop is visible.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Screen Saver") {
                LabeledContent("Status", value: screenSaver.isInstalled ? "Installed" : "Set a wallpaper as screen saver to install")
                Toggle("Play sound", isOn: $screenSaver.soundEnabled)
                Slider(value: $screenSaver.volume, in: 0...1) { Text("Volume") } onEditingChanged: { if !$0 { screenSaver.applyVolume() } }
                    .disabled(!screenSaver.soundEnabled)
                Button("Open Screen Saver Settings…") { screenSaver.openSystemSettings() }
                Text("Pick “StayLive” in System Settings → Screen Saver. Apple's Aerial screen saver uses your lock-screen video but can't play sound.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Lock Screen") {
                LabeledContent("Replacing", value: lockScreen.aerialName.map { "Apple \($0)" } ?? "No Aerial selected")
                Button("Restore Apple's Original") { lockScreen.restoreOriginal() }
                    .disabled(!lockScreen.hasBackup || lockScreen.installedID == nil || lockScreen.installingID != nil)
                Text("Choose which Aerial to replace in System Settings → Wallpaper.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Built-in Wallpapers") {
                Button("Restore Built-in Wallpapers") { BuiltInLibrary.shared.restoreMissing() }
                Text("Recreates any built-in wallpapers you removed. They're generated on your Mac; nothing is downloaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage") {
                Button("Show Library Folder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.root]) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .preferredColorScheme(.dark)
        .onAppear { lockScreen.refresh() }
    }
}
