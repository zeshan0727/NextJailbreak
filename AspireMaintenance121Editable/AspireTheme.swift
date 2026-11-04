import SwiftUI

// MARK: - App Theme

enum AspireAppTheme: String, CaseIterable, Identifiable {
    case professionalGreen
    case corporateBlue
    case premiumGold
    case minimalLight
    case darkMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .professionalGreen: return "Professional Green"
        case .corporateBlue: return "Corporate Blue"
        case .premiumGold: return "Premium Gold"
        case .minimalLight: return "Minimal Light"
        case .darkMode: return "Dark Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .professionalGreen: return "Aspire brand • professional and modern"
        case .corporateBlue: return "Modern • trustworthy • business focused"
        case .premiumGold: return "Executive • premium • elegant"
        case .minimalLight: return "Clean • bright • low visual noise"
        case .darkMode: return "Dark surfaces • green and gold accents"
        }
    }

    var icon: String {
        switch self {
        case .professionalGreen: return "leaf.fill"
        case .corporateBlue: return "square.3.layers.3d.top.filled"
        case .premiumGold: return "crown.fill"
        case .minimalLight: return "circle.grid.2x2.fill"
        case .darkMode: return "moon.stars.fill"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .darkMode: return .dark
        case .minimalLight, .professionalGreen, .corporateBlue, .premiumGold: return .light
        }
    }

    var primary: Color {
        switch self {
        case .professionalGreen, .minimalLight, .darkMode:
            return Color(red: 0.10, green: 0.48, blue: 0.29)
        case .corporateBlue:
            return Color(red: 0.04, green: 0.27, blue: 0.58)
        case .premiumGold:
            return Color(red: 0.73, green: 0.47, blue: 0.06)
        }
    }

    var accent: Color {
        switch self {
        case .professionalGreen, .corporateBlue, .darkMode:
            return Color(red: 0.91, green: 0.63, blue: 0.15)
        case .premiumGold:
            return Color(red: 0.12, green: 0.39, blue: 0.25)
        case .minimalLight:
            return Color(red: 0.25, green: 0.45, blue: 0.95)
        }
    }

    var previewBackground: Color {
        switch self {
        case .darkMode: return Color(red: 0.07, green: 0.08, blue: 0.09)
        case .premiumGold: return Color(red: 0.99, green: 0.98, blue: 0.94)
        case .corporateBlue: return Color(red: 0.95, green: 0.97, blue: 1.0)
        case .minimalLight: return Color.white
        case .professionalGreen: return Color(red: 0.95, green: 0.98, blue: 0.96)
        }
    }

    static var selected: AspireAppTheme {
        let raw = UserDefaults.standard.string(forKey: ThemePreferenceKeys.appTheme) ?? AspireAppTheme.professionalGreen.rawValue
        return AspireAppTheme(rawValue: raw) ?? .professionalGreen
    }
}

enum ThemePreferenceKeys {
    static let appTheme = "aspire.appearance.theme"
    static let compactDensity = "aspire.appearance.compactDensity"
    static let gradientHeader = "aspire.appearance.gradientHeader"
}

struct ThemeAppearanceSettingsView: View {
    @AppStorage(ThemePreferenceKeys.appTheme) private var themeRaw = AspireAppTheme.professionalGreen.rawValue
    @AppStorage(ThemePreferenceKeys.compactDensity) private var compactDensity = false
    @AppStorage(ThemePreferenceKeys.gradientHeader) private var gradientHeader = true

    private var selectedTheme: AspireAppTheme {
        AspireAppTheme(rawValue: themeRaw) ?? .professionalGreen
    }

    var body: some View {
        List {
            Section {
                ThemeLivePreview(theme: selectedTheme)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Live Preview")
            }

            Section("App Theme") {
                ForEach(AspireAppTheme.allCases) { theme in
                    Button {
                        themeRaw = theme.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.primary.opacity(0.14))
                                    .frame(width: 40, height: 40)
                                Image(systemName: theme.icon)
                                    .foregroundStyle(theme.primary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTheme == theme {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Interface") {
                Toggle("Gradient dashboard header", isOn: $gradientHeader)
                Toggle("Compact density", isOn: $compactDensity)
                LabeledContent("Dashboard Layout", value: "Configured separately")
            }
        }
        .navigationTitle("Theme & Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeLivePreview: View {
    let theme: AspireAppTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ASPIRE").font(.headline.weight(.heavy)).foregroundStyle(theme.primary)
                    Text(theme.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: theme.icon).foregroundStyle(theme.accent)
            }
            HStack(spacing: 8) {
                previewCard("Revenue", "AED 38,450", icon: "chart.line.uptrend.xyaxis")
                previewCard("Visits", "42 / 56", icon: "calendar.badge.clock")
            }
            HStack(spacing: 5) {
                Capsule().fill(theme.primary).frame(height: 6)
                Capsule().fill(theme.accent).frame(height: 6)
                Capsule().fill(theme.primary.opacity(0.22)).frame(height: 6)
            }
        }
        .padding(14)
        .background(theme.previewBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.primary.opacity(0.14)))
    }

    private func previewCard(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(theme.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.bold))
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Color(.secondarySystemGroupedBackground).opacity(theme == .darkMode ? 0.65 : 0.95), in: RoundedRectangle(cornerRadius: 12))
    }
}
