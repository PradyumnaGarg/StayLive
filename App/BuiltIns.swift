import AVFoundation
import AppKit

enum BuiltInStyle: String, CaseIterable {
    case aurora, colorFlow, starfield, duskWaves

    var name: String {
        switch self {
        case .aurora: return "Aurora"
        case .colorFlow: return "Color Flow"
        case .starfield: return "Starfield"
        case .duskWaves: return "Dusk Waves"
        }
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

enum BuiltInRenderer {
    static let width = 1920, height = 1080, fps = 30
    static let seconds = 20.0
    static var frameCount: Int { Int(seconds) * fps }

    static func render(_ style: BuiltInStyle, to url: URL, progress: (Double) -> Void) throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var bufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &bufferOut)
            guard let buffer = bufferOut else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            let phase = Double(frame) / Double(frameCount) * 2 * .pi
            draw(style, in: context, phase: phase)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData { usleep(1000) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            if frame % 15 == 0 { progress(Double(frame) / Double(frameCount)) }
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        progress(1)
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func fillBackground(_ ctx: CGContext, top: CGColor, bottom: CGColor) {
        let gradient = CGGradient(colorsSpace: nil, colors: [bottom, top] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }

    private static func glow(_ ctx: CGContext, at p: CGPoint, radius: Double, color c: CGColor) {
        let clear = c.copy(alpha: 0)!
        let gradient = CGGradient(colorsSpace: nil, colors: [c, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    }

    private static func draw(_ style: BuiltInStyle, in ctx: CGContext, phase t: Double) {
        let w = Double(width), h = Double(height)
        switch style {
        case .aurora:
            fillBackground(ctx, top: color(0.01, 0.02, 0.07), bottom: color(0.02, 0.06, 0.12))
            var rng = SeededRandom(7)
            for _ in 0..<220 {
                let x = rng.next() * w, y = h * 0.35 + rng.next() * h * 0.65, size = 0.6 + rng.next() * 1.6
                ctx.setFillColor(color(1, 1, 1, 0.25 + 0.55 * rng.next()))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
            ctx.setBlendMode(.plusLighter)
            let ribbons: [(base: Double, amp: Double, k: Double, speed: Double, c: CGColor)] = [
                (0.66, 0.07, 1.4, 1, color(0.15, 0.95, 0.60, 0.016)),
                (0.74, 0.05, 1.1, -1, color(0.25, 0.70, 1.00, 0.013)),
                (0.58, 0.04, 2.0, 2, color(0.65, 0.35, 1.00, 0.011)),
            ]
            for r in ribbons {
                for layer in 0..<28 {
                    let offset = Double(layer) * 0.004
                    let path = CGMutablePath()
                    let steps = 120
                    for i in 0...steps {
                        let x = Double(i) / Double(steps)
                        let y = r.base + offset + r.amp * sin(r.k * x * 2 * .pi + r.speed * t) + 0.02 * sin(5 * x * .pi + 2 * t)
                        let p = CGPoint(x: x * w, y: y * h)
                        i == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                    for i in stride(from: steps, through: 0, by: -1) {
                        let x = Double(i) / Double(steps)
                        let y = r.base - 0.16 + offset * 0.5 + r.amp * sin(r.k * x * 2 * .pi + r.speed * t)
                        path.addLine(to: CGPoint(x: x * w, y: y * h))
                    }
                    path.closeSubpath()
                    ctx.addPath(path)
                    ctx.setFillColor(r.c)
                    ctx.fillPath()
                }
            }
            ctx.setBlendMode(.normal)

        case .colorFlow:
            fillBackground(ctx, top: color(0.05, 0.03, 0.10), bottom: color(0.02, 0.02, 0.05))
            ctx.setBlendMode(.plusLighter)
            let blobs: [(a: Double, b: Double, p: Double, c: CGColor)] = [
                (1, 2, 0.0, color(1.00, 0.30, 0.55, 0.55)),
                (2, 1, 1.3, color(0.45, 0.35, 1.00, 0.55)),
                (1, 1, 2.6, color(1.00, 0.60, 0.25, 0.45)),
                (3, 2, 3.9, color(0.20, 0.70, 1.00, 0.45)),
                (2, 3, 5.0, color(0.85, 0.30, 1.00, 0.40)),
            ]
            for blob in blobs {
                let x = w * (0.5 + 0.32 * sin(blob.a * t + blob.p))
                let y = h * (0.5 + 0.30 * cos(blob.b * t + blob.p * 0.7))
                glow(ctx, at: CGPoint(x: x, y: y), radius: h * 0.75, color: blob.c)
            }
            ctx.setBlendMode(.normal)

        case .starfield:
            fillBackground(ctx, top: color(0.02, 0.02, 0.06), bottom: color(0.03, 0.01, 0.08))
            ctx.setBlendMode(.plusLighter)
            glow(ctx, at: CGPoint(x: w * (0.3 + 0.05 * sin(t)), y: h * 0.6), radius: h * 0.7, color: color(0.35, 0.15, 0.6, 0.35))
            glow(ctx, at: CGPoint(x: w * (0.75 + 0.05 * cos(t)), y: h * 0.35), radius: h * 0.6, color: color(0.1, 0.3, 0.6, 0.3))
            var rng = SeededRandom(42)
            for _ in 0..<650 {
                let depth = rng.next()
                let loops = depth > 0.7 ? 2.0 : 1.0
                let x = (rng.next() + loops * t / (2 * .pi)).truncatingRemainder(dividingBy: 1) * w
                let y = rng.next() * h
                let size = 1.4 + depth * 3.2
                let twinkle = 0.55 + 0.45 * sin(Double(Int(rng.next() * 4) + 1) * t + rng.next() * 6.28)
                ctx.setFillColor(color(0.85 + 0.15 * depth, 0.92, 1, twinkle * (0.5 + 0.5 * depth)))
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: size, height: size))
            }
            ctx.setBlendMode(.normal)

        case .duskWaves:
            let sky = CGGradient(colorsSpace: nil, colors: [color(0.98, 0.55, 0.35), color(0.55, 0.25, 0.55), color(0.10, 0.08, 0.25)] as CFArray,
                                 locations: [0.35, 0.6, 1])!
            ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: h), options: [])
            ctx.setBlendMode(.plusLighter)
            glow(ctx, at: CGPoint(x: w * 0.5, y: h * 0.42), radius: h * 0.35, color: color(1, 0.75, 0.45, 0.55))
            ctx.setBlendMode(.normal)
            ctx.setFillColor(color(1, 0.85, 0.6, 0.95))
            ctx.fillEllipse(in: CGRect(x: w * 0.5 - h * 0.07, y: h * 0.42 - h * 0.07, width: h * 0.14, height: h * 0.14))
            let waves: [(base: Double, amp: Double, k: Double, speed: Double, c: CGColor)] = [
                (0.40, 0.012, 3, 1, color(0.30, 0.18, 0.40, 0.9)),
                (0.33, 0.016, 2, -1, color(0.20, 0.12, 0.32, 0.92)),
                (0.25, 0.020, 4, 2, color(0.13, 0.08, 0.24, 0.95)),
                (0.16, 0.024, 3, -2, color(0.08, 0.05, 0.16, 0.97)),
                (0.07, 0.028, 2, 1, color(0.04, 0.03, 0.10, 1)),
            ]
            for wave in waves {
                let path = CGMutablePath()
                path.move(to: .zero)
                let steps = 160
                for i in 0...steps {
                    let x = Double(i) / Double(steps)
                    let y = wave.base + wave.amp * sin(wave.k * x * 2 * .pi + wave.speed * t)
                        + wave.amp * 0.4 * sin(7 * x * 2 * .pi - 2 * wave.speed * t)
                    path.addLine(to: CGPoint(x: x * w, y: y * h))
                }
                path.addLine(to: CGPoint(x: w, y: 0))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(wave.c)
                ctx.fillPath()
            }
        }
    }
}

@MainActor
final class BuiltInLibrary: ObservableObject {
    static let shared = BuiltInLibrary()

    @Published private(set) var currentStyle: BuiltInStyle?
    @Published private(set) var progress: Double = 0
    private var running = false

    var isGenerating: Bool { currentStyle != nil }

    func ensureInstalled() {
        guard !UserDefaults.standard.bool(forKey: "didInstallBuiltIns") else { return }
        restoreMissing { UserDefaults.standard.set(true, forKey: "didInstallBuiltIns") }
    }

    func restoreMissing(completion: (() -> Void)? = nil) {
        guard !running else { return }
        let existing = Set(LibraryStore.shared.items.compactMap(\.builtInKey))
        let missing = BuiltInStyle.allCases.filter { !existing.contains($0.rawValue) }
        guard !missing.isEmpty else { completion?(); return }
        running = true
        Task { [weak self] in
            for style in missing {
                await MainActor.run { self?.currentStyle = style; self?.progress = 0 }
                let id = UUID()
                let url = AppPaths.videos.appendingPathComponent("\(id.uuidString).mov")
                do {
                    try await Task.detached(priority: .utility) {
                        try BuiltInRenderer.render(style, to: url) { p in
                            Task { @MainActor in self?.progress = p }
                        }
                    }.value
                    await LibraryStore.shared.addGenerated(id: id, url: url, name: style.name, builtInKey: style.rawValue)
                } catch {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            await MainActor.run {
                self?.currentStyle = nil
                self?.running = false
                completion?()
            }
        }
    }
}
