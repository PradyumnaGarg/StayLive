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
}

struct LoopingPlayer: NSViewRepresentable {
    let url: URL?
    func makeNSView(context: Context) -> LoopingPlayerNSView { LoopingPlayerNSView() }
    func updateNSView(_ view: LoopingPlayerNSView, context: Context) { view.play(url) }
    static func dismantleNSView(_ view: LoopingPlayerNSView, coordinator: ()) { view.stop() }
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
            Group {
                if hovering {
                    LoopingPlayer(url: library.videoURL(wallpaper))
                } else if let image = library.thumbnail(wallpaper) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

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

struct FeaturedCarousel: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @Binding var focusedID: UUID?
    var onShowDetails: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width * 0.62, 780)
            let cardHeight = cardWidth * 9 / 16
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(library.items) { w in
                            CarouselCard(wallpaper: w, isFocused: focusedID == w.id, onShowDetails: onShowDetails)
                                .frame(width: cardWidth, height: cardHeight)
                                .id(w.id)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content
                                        .scaleEffect(phase.isIdentity ? 1 : 0.82)
                                        .opacity(phase.isIdentity ? 1 : 0.55)
                                        .blur(radius: phase.isIdentity ? 0 : 5)
                                        .rotation3DEffect(.degrees(phase.value * -22), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                                }
                                .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { focusedID = w.id } }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedID, anchor: .center)
                .contentMargins(.horizontal, (geo.size.width - cardWidth) / 2, for: .scrollContent)
                .scrollClipDisabled()

                HStack {
                    arrow("chevron.left", offset: -1).keyboardShortcut(.leftArrow, modifiers: [])
                    Spacer()
                    arrow("chevron.right", offset: 1).keyboardShortcut(.rightArrow, modifiers: [])
                }
                .padding(.horizontal, max(8, (geo.size.width - cardWidth) / 2 - 64))
            }
            .frame(width: geo.size.width, height: cardHeight)
            .onAppear { carouselHeight = cardHeight }
            .onChange(of: geo.size.width) { carouselHeight = min(geo.size.width * 0.62, 780) * 9 / 16 }
        }
        .frame(height: carouselHeight)
        .padding(.vertical, 12)
    }

    @State private var carouselHeight: CGFloat = 380

    private func arrow(_ symbol: String, offset: Int) -> some View {
        Button { move(offset) } label: {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.cardStroke))
        }
        .buttonStyle(.plain)
        .disabled(library.items.count < 2)
    }

    private func move(_ offset: Int) {
        guard let index = library.items.firstIndex(where: { $0.id == focusedID }) else {
            focusedID = library.items.first?.id
            return
        }
        let next = (index + offset + library.items.count) % library.items.count
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { focusedID = library.items[next].id }
    }
}

struct CarouselCard: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    let wallpaper: Wallpaper
    let isFocused: Bool
    var onShowDetails: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isFocused {
                    LoopingPlayer(url: library.videoURL(wallpaper))
                } else if let image = library.thumbnail(wallpaper) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Theme.panel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(colors: [.clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)

            if isFocused {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(wallpaper.name)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .lineLimit(1)
                            Text("\(wallpaper.resolutionLabel) · \(wallpaper.durationLabel)\(wallpaper.hasAudio == true ? " · Sound" : "")")
                                .font(.callout).foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        HStack(spacing: 6) {
                            if desktop.currentID == wallpaper.id { Badge(text: "On desktop", symbol: "desktopcomputer", compact: true) }
                            if lockScreen.installedID == wallpaper.id { Badge(text: "On lock screen", symbol: "lock.fill", compact: true) }
                            if screenSaver.currentID == wallpaper.id { Badge(text: "Screen saver", symbol: "sparkles.tv", compact: true) }
                        }
                    }
                    actionBar
                }
                .foregroundStyle(.white)
                .padding(20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.cardStroke))
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2), radius: isFocused ? 28 : 10, y: isFocused ? 14 : 6)
        .animation(.easeOut(duration: 0.25), value: isFocused)
        .contextMenu {
            Button("Set as Desktop") { desktop.setWallpaper(wallpaper.id) }
            Button("Set as Lock Screen") { lockScreen.apply(wallpaper) }
            Button("Set as Screen Saver") { screenSaver.set(wallpaper) }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button { desktop.setWallpaper(wallpaper.id); lockScreen.apply(wallpaper); screenSaver.set(wallpaper) } label: {
                Label("Use Everywhere", systemImage: "sparkles")
            }
            .buttonStyle(GradientButtonStyle())
            glassIcon("desktopcomputer", "Set as desktop") { desktop.setWallpaper(wallpaper.id) }
            glassIcon("lock", "Set as lock screen") { lockScreen.apply(wallpaper) }
            glassIcon("sparkles.tv", "Set as screen saver") { screenSaver.set(wallpaper) }
            Spacer()
            if lockScreen.convertingID == wallpaper.id {
                HStack(spacing: 8) {
                    GradientRing(value: lockScreen.progress)
                    Text("~\(LockScreenController.durationText(lockScreen.remainingSeconds(wallpaper)))").font(.caption).monospacedDigit()
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
            glassIcon("info.circle", "Details") { onShowDetails() }
        }
    }

    private func glassIcon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.medium))
                .frame(width: 42, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct StatusBar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController

    var body: some View {
        HStack(spacing: 14) {
            Button { desktop.togglePause() } label: {
                Image(systemName: desktop.isUserPaused ? "play.fill" : "pause.fill")
                    .frame(width: 34, height: 34)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(desktop.currentID == nil)
            .help(desktop.isUserPaused ? "Resume desktop" : "Pause desktop")

            item("desktopcomputer", "Desktop", library.item(desktop.currentID)?.name ?? "None",
                 detail: desktop.isPlaying ? "Playing" : (desktop.isUserPaused ? "Paused" : "Idle"))
            Divider().frame(height: 26)
            item("lock.fill", "Lock screen", library.item(lockScreen.installedID)?.name
                 ?? lockScreen.aerialName.map { "Apple \($0)" } ?? "Apple default")
            Divider().frame(height: 26)
            item("sparkles.tv", "Screen saver", library.item(screenSaver.currentID)?.name ?? "Not set")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    private func item(_ symbol: String, _ title: String, _ value: String, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(detail.map { "\(value) · \($0)" } ?? value).font(.callout.weight(.medium)).lineLimit(1)
            }
        }
        .frame(maxWidth: 260, alignment: .leading)
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    @State private var selection: UUID?
    @State private var showInspector = false
    @State private var importing = false
    @State private var dropTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !library.items.isEmpty {
                    FeaturedCarousel(focusedID: $selection) { showInspector = true }
                        .padding(.horizontal, -28)
                    StatusBar()
                }
                HStack(alignment: .firstTextBaseline) {
                    Capsule().fill(Theme.accent).frame(width: 4, height: 22).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                    Text("Library").font(.title2.bold())
                    Text("\(library.items.count)").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    if library.isImporting { ProgressView().controlSize(.small) }
                }
                if library.items.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(library.items) { w in
                            WallpaperCard(wallpaper: w, isSelected: selection == w.id)
                                .onTapGesture { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { selection = w.id } }
                                .onTapGesture(count: 2) { desktop.setWallpaper(w.id) }
                                .contextMenu { contextMenu(for: w) }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(AmbientBackground(image: library.item(selection ?? desktop.currentID).flatMap { library.thumbnail($0) })
            .animation(.easeInOut(duration: 0.6), value: selection))
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { if selection == nil { selection = desktop.currentID ?? library.items.first?.id } }
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
            Task { if let first = await library.importVideos(videos).first { selection = first.id; showInspector = true } }
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { importing = true } label: { Label("Add Videos", systemImage: "plus") }
                    .help("Add videos to your library")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                    .disabled(selection == nil)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { if let first = await library.importVideos(urls).first { selection = first.id; showInspector = true } }
        }
        .inspector(isPresented: $showInspector) {
            if let w = library.item(selection) {
                InspectorView(wallpaper: w)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            } else {
                ContentUnavailableView("No Selection", systemImage: "photo.on.rectangle", description: Text("Select a wallpaper to see details."))
            }
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

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Your library is empty").font(.title3.bold())
            Text("Drag videos here or click Add Videos.").foregroundStyle(.secondary)
            Button("Add Videos…") { importing = true }.buttonStyle(GradientButtonStyle()).fixedSize()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [8, 6])))
    }

    @ViewBuilder
    private func contextMenu(for w: Wallpaper) -> some View {
        Button("Set as Desktop") { desktop.setWallpaper(w.id) }
        Button("Set as Lock Screen") { lockScreen.apply(w) }
        Button("Set as Screen Saver") { screenSaver.set(w) }
        Button("Use Everywhere") { desktop.setWallpaper(w.id); lockScreen.apply(w); screenSaver.set(w) }
        Divider()
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([library.videoURL(w)]) }
        Button("Remove from Library", role: .destructive) {
            if selection == w.id { selection = nil }
            library.remove(w)
        }
    }
}

struct InspectorView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var desktop: DesktopController
    @EnvironmentObject private var lockScreen: LockScreenController
    @EnvironmentObject private var screenSaver: ScreenSaverController
    let wallpaper: Wallpaper
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LoopingPlayer(url: library.videoURL(wallpaper))
                    .aspectRatio(16 / 9, contentMode: .fit)
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
        .onChange(of: wallpaper.id) { name = wallpaper.name }
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
                    LoopingPlayer(url: library.videoURL(current))
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
                Button("Open Library") {
                    openWindow(id: "library")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
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
            Section("Storage") {
                Button("Show Library Folder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.root]) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .frame(width: 440)
        .onAppear { lockScreen.refresh() }
    }
}
