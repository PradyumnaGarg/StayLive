import SwiftUI

enum Theme {
    static let pink = Color(red: 1.00, green: 0.36, blue: 0.58)
    static let violet = Color(red: 0.60, green: 0.36, blue: 1.00)
    static let blue = Color(red: 0.27, green: 0.50, blue: 1.00)

    static let accent = Color.accentColor

    static let background = LinearGradient(
        colors: [Color(red: 0.04, green: 0.04, blue: 0.08),
                 Color(red: 0.08, green: 0.05, blue: 0.15),
                 Color(red: 0.03, green: 0.06, blue: 0.13)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let panel = LinearGradient(
        colors: [Color(red: 0.09, green: 0.07, blue: 0.16), Color(red: 0.05, green: 0.05, blue: 0.10)],
        startPoint: .top, endPoint: .bottom)

    static let cardStroke = LinearGradient(
        colors: [.white.opacity(0.18), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct AmbientBackground: View {
    var image: NSImage?

    var body: some View {
        ZStack {
            Theme.background
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 90)
                    .saturation(1.4)
                    .opacity(0.45)
                    .transition(.opacity)
            }
            RadialGradient(colors: [Theme.violet.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Theme.pink.opacity(0.12), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
        .clipped()
        .ignoresSafeArea()
    }
}

struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .shadow(color: .black.opacity(isEnabled ? 0.25 : 0), radius: 6, y: 3)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(.white.opacity(configuration.isPressed ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardStroke))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

struct GradientProgressBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(8, geo.size.width * min(max(value, 0), 1)))
                    .animation(.easeOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 6)
    }
}

struct GradientRing: View {
    var value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: value)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
    }
}
