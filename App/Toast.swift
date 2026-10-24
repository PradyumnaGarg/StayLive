import AppKit
import SwiftUI
import UserNotifications

struct Toast: Identifiable, Equatable {
    enum Style { case success, info, error }
    let id = UUID()
    let title: String
    var message: String?
    var symbol: String
    var style: Style
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: Toast?
    @Published var systemNotifications = UserDefaults.standard.bool(forKey: "systemNotifications") {
        didSet {
            UserDefaults.standard.set(systemNotifications, forKey: "systemNotifications")
            if systemNotifications { requestAuthorization() }
        }
    }
    @Published private(set) var notificationsDenied = false

    func show(_ title: String, message: String? = nil, symbol: String = "checkmark.circle.fill",
              style: Toast.Style = .success, notify: Bool = false) {
        let toast = Toast(title: title, message: message, symbol: symbol, style: style)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { current = toast }
        Task {
            try? await Task.sleep(for: .seconds(message == nil ? 3 : 4.5))
            if current?.id == toast.id { withAnimation(.easeOut(duration: 0.25)) { current = nil } }
        }
        if notify && systemNotifications && !NSApp.isActive { postNotification(title: title, body: message) }
    }

    func dismiss() { withAnimation(.easeOut(duration: 0.2)) { current = nil } }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in
                self.notificationsDenied = !granted
                if !granted { self.systemNotifications = false }
            }
        }
    }

    private func postNotification(title: String, body: String?) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

struct ToastView: View {
    let toast: Toast

    private var tint: Color {
        switch toast.style {
        case .success: return .green
        case .info: return .accentColor
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: toast.symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(toast.title).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let message = toast.message {
                    Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { ToastCenter.shared.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
