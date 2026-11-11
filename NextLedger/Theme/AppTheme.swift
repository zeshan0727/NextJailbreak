import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System Default"
    case light = "Light"
    case dark = "Black"

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppVisualTheme: String, CaseIterable, Identifiable {
    case native = "Native Classic"
    case glass = "iOS 26 Glass Style"
    var id: String { rawValue }
}

enum AppTheme {
    static let purple = Color(red: 0.39, green: 0.25, blue: 0.93)
    static let blue = Color(red: 0.16, green: 0.48, blue: 0.96)
    static let teal = Color(red: 0.06, green: 0.72, blue: 0.65)
    static let green = Color(red: 0.09, green: 0.70, blue: 0.42)
    static let orange = Color(red: 0.98, green: 0.50, blue: 0.16)
    static let red = Color(red: 0.94, green: 0.24, blue: 0.32)
    static let page = Color(uiColor: .systemGroupedBackground)

    static let balanceGradient = LinearGradient(
        colors: [purple, blue, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func categoryColor(_ category: String) -> Color {
        let colors = [purple, blue, teal, green, orange, red, .pink, .indigo]
        let index = Int(category.hashValue.magnitude % UInt(colors.count))
        return colors[index]
    }

    static func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "restaurant": return "fork.knife"
        case "grocery": return "basket.fill"
        case "food": return "fork.knife"
        case "shopping": return "bag.fill"
        case "transport": return "car.fill"
        case "bills": return "doc.text.fill"
        case "fuel": return "fuelpump.fill"
        case "health": return "cross.case.fill"
        case "home": return "house.fill"
        case "family": return "person.2.fill"
        case "entertainment": return "gamecontroller.fill"
        case "salary": return "banknote.fill"
        case "business": return "briefcase.fill"
        case "refund": return "arrow.uturn.backward.circle.fill"
        case "gift": return "gift.fill"
        case "investment": return "chart.line.uptrend.xyaxis"
        default: return "square.grid.2x2.fill"
        }
    }
}

extension View {
    @ViewBuilder
    func dailyLedgerGlass(tint: Color = AppTheme.purple, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.tint(tint.opacity(0.22)).interactive(), in: .rect(cornerRadius: 22))
            } else {
                self.glassEffect(.regular.tint(tint.opacity(0.16)), in: .rect(cornerRadius: 22))
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 0.8)
                }
                .shadow(color: tint.opacity(0.18), radius: 12, y: 6)
        }
        #else
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.28), lineWidth: 0.8)
            }
            .shadow(color: tint.opacity(0.18), radius: 12, y: 6)
        #endif
    }
}

enum DisplayFormat {
    static func currency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? "\(code) \(NSDecimalNumber(decimal: amount).stringValue)"
    }

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}
