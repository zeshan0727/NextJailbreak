import SwiftUI

/// Adaptive, accessible design system. Cards use semantic UIKit backgrounds so
/// they automatically adjust to the selected light/dark appearance.
enum SignerDesign {
    static let blue = Color(red: 0.13, green: 0.40, blue: 0.98)
    static let teal = Color(red: 0.04, green: 0.74, blue: 0.73)
    static let violet = Color(red: 0.43, green: 0.32, blue: 0.91)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator).opacity(0.22)
    static let hero = LinearGradient(
        colors: [Color(red: 0.09, green: 0.22, blue: 0.54), blue, violet],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

enum SignerAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SignerModernGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            configuration.content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SignerDesign.hairline, lineWidth: 0.7)
        }
    }
}

struct SignerSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SignerStatusDot: View {
    let ready: Bool
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(ready ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SignerDesign.card, in: Capsule())
    }
}

struct SignerMetricCard: View {
    let icon: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SignerDesign.blue)
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(SignerDesign.hairline, lineWidth: 0.7)
        }
    }
}
