import SwiftUI

/// Remote-only visual options. They never change TV protocols, identities,
/// saved pairing, command mappings, or the active casting session.
enum NexaRemoteStyle: String, CaseIterable, Identifiable {
    case modernDark, cleanLight, minimal, neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modernDark: return "Modern Dark"
        case .cleanLight: return "Clean Light"
        case .minimal: return "Minimal"
        case .neon: return "Neon"
        }
    }

    var subtitle: String {
        switch self {
        case .modernDark: return "Cinematic orange"
        case .cleanLight: return "Bright and refined"
        case .minimal: return "Quiet and distraction-free"
        case .neon: return "Electric blue glow"
        }
    }

    var isLight: Bool { self == .cleanLight }

    var canvas: Color {
        switch self {
        case .modernDark: return Color(red: 0.027, green: 0.044, blue: 0.090)
        case .cleanLight: return Color(red: 0.958, green: 0.970, blue: 0.989)
        case .minimal: return Color(red: 0.047, green: 0.051, blue: 0.061)
        case .neon: return Color(red: 0.010, green: 0.032, blue: 0.090)
        }
    }

    var surface: Color {
        switch self {
        case .modernDark: return Color(red: 0.070, green: 0.101, blue: 0.165)
        case .cleanLight: return .white
        case .minimal: return Color(red: 0.101, green: 0.110, blue: 0.126)
        case .neon: return Color(red: 0.025, green: 0.070, blue: 0.150)
        }
    }

    var key: Color {
        switch self {
        case .modernDark: return Color(red: 0.112, green: 0.157, blue: 0.240)
        case .cleanLight: return Color(red: 0.897, green: 0.920, blue: 0.953)
        case .minimal: return Color(red: 0.157, green: 0.169, blue: 0.188)
        case .neon: return Color(red: 0.060, green: 0.110, blue: 0.220)
        }
    }

    var text: Color {
        isLight ? Color(red: 0.085, green: 0.112, blue: 0.169) : .white
    }

    var secondary: Color {
        isLight ? Color(red: 0.43, green: 0.47, blue: 0.52) : Color(red: 0.64, green: 0.69, blue: 0.77)
    }

    var accent: Color {
        self == .neon ? Color(red: 0.04, green: 0.66, blue: 1.0) :
            Color(red: 1.0, green: 0.46, blue: 0.02)
    }

    var stroke: Color {
        isLight ? .black.opacity(0.08) : accent.opacity(self == .neon ? 0.48 : 0.17)
    }

    var shadow: Color {
        accent.opacity(self == .neon ? 0.35 : 0.16)
    }
}

enum NexaRemoteLayout: String, CaseIterable, Identifiable {
    case dpad, touchpad, keys
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dpad: return "D-Pad"
        case .touchpad: return "Touchpad"
        case .keys: return "Keys"
        }
    }
    var icon: String {
        switch self {
        case .dpad: return "circle.grid.cross"
        case .touchpad: return "hand.draw"
        case .keys: return "square.grid.3x3.fill"
        }
    }
}

/// Non-interactive miniature, used only in the style chooser.
struct NexaRemoteStyleSwatch: View {
    let style: NexaRemoteStyle
    let selected: Bool

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(style.canvas)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(style.accent)
                            .frame(width: 9, height: 9)
                        Capsule()
                            .fill(style.key)
                            .frame(width: 34, height: 12)
                        Capsule()
                            .fill(style.key)
                            .frame(width: 34, height: 12)
                    }
                    ZStack {
                        Circle()
                            .fill(style.key)
                            .frame(width: 80, height: 80)
                            .overlay(Circle().strokeBorder(style.stroke, lineWidth: 1))
                        Circle()
                            .fill(style.canvas)
                            .frame(width: 35, height: 35)
                            .overlay(Circle().strokeBorder(style.accent, lineWidth: 2))
                        Text("OK")
                            .foregroundStyle(style.text)
                            .font(.system(size: 12, weight: .bold))
                    }
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule()
                                .fill(style.key)
                                .frame(width: 30, height: 13)
                        }
                    }
                }
            }
            .frame(height: 150)
            .overlay(RoundedRectangle(cornerRadius: 15)
                .strokeBorder(selected ? style.accent : .clear, lineWidth: 2.5))
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(style.accent) }
                Text(style.title).font(.caption.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(style.subtitle).font(.system(size: 10))
                .foregroundStyle(.secondary).lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
