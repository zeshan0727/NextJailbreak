import SwiftUI

enum NSTheme {
    static let background = Color(red: 0.025, green: 0.035, blue: 0.075)
    static let elevated = Color(red: 0.065, green: 0.080, blue: 0.145)
    static let cyan = Color(red: 0.20, green: 0.86, blue: 1.00)
    static let blue = Color(red: 0.25, green: 0.48, blue: 1.00)
    static let violet = Color(red: 0.57, green: 0.35, blue: 1.00)
    static let mint = Color(red: 0.30, green: 0.94, blue: 0.72)
    static let warning = Color(red: 1.00, green: 0.70, blue: 0.25)
    static let danger = Color(red: 1.00, green: 0.34, blue: 0.45)
    static let textSecondary = Color.white.opacity(0.62)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [cyan, blue, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var softGradient: LinearGradient {
        LinearGradient(
            colors: [blue.opacity(0.35), violet.opacity(0.22), cyan.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct NSBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                NSTheme.background,
                NSTheme.elevated.opacity(0.42),
                NSTheme.background
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct NSGlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(NSTheme.elevated.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct NSPageHeader: View {
    let eyebrow: String?
    let title: String
    let subtitle: String
    let systemImage: String

    init(eyebrow: String? = nil, title: String, subtitle: String, systemImage: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NSIconBadge(systemImage: systemImage, size: 54)

            VStack(alignment: .leading, spacing: 5) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.25)
                        .foregroundStyle(NSTheme.cyan)
                }

                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(NSTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

struct NSIconBadge: View {
    let systemImage: String
    var size: CGFloat = 46
    var tint: Color = NSTheme.cyan

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                        .fill(NSTheme.accentGradient)
                    RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                        .fill(tint.opacity(0.12))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }
}

struct NSStatusChip: View {
    let text: String
    let systemImage: String
    var tint: Color = NSTheme.cyan

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.23), lineWidth: 1))
    }
}

struct NSSectionHeader: View {
    let title: String
    let subtitle: String?
    let systemImage: String

    init(_ title: String, subtitle: String? = nil, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NSTheme.cyan)
                .frame(width: 30, height: 30)
                .background(NSTheme.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(NSTheme.textSecondary)
                }
            }
            Spacer()
        }
    }
}

struct NSPrimaryButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                Group {
                    if destructive {
                        LinearGradient(
                            colors: [NSTheme.danger, Color(red: 0.80, green: 0.14, blue: 0.33)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        NSTheme.accentGradient
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.90 : 1)
    }
}

struct NSSecondaryButtonStyle: ButtonStyle {
    var tint: Color = NSTheme.cyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(tint.opacity(configuration.isPressed ? 0.08 : 0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct NSModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}

extension View {
    func nsPagePadding() -> some View {
        self.padding(.horizontal, 16).padding(.top, 10)
    }

    func nsHideListBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color.clear)
    }
}
