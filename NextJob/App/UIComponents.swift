import SwiftUI

extension AppTheme {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppPalette {
    static let accent = Color(red: 0.16, green: 0.45, blue: 0.98)
    static let cyan = Color(red: 0.10, green: 0.72, blue: 0.82)
    static let purple = Color(red: 0.50, green: 0.32, blue: 0.95)
    static let green = Color(red: 0.14, green: 0.70, blue: 0.42)
    static let orange = Color(red: 0.96, green: 0.55, blue: 0.16)
    static let red = Color(red: 0.93, green: 0.28, blue: 0.32)

    static func status(_ status: JobStatus) -> Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress: return accent
        case .waitingForDocuments: return orange
        case .readyForReview: return purple
        case .completed: return green
        }
    }
}

struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

struct StatusBadge: View {
    let status: JobStatus

    var body: some View {
        Label(status.title, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppPalette.status(status))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppPalette.status(status).opacity(0.12), in: Capsule())
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        .glassCard()
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(AppPalette.accent)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .glassCard()
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppPalette.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
