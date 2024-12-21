import SwiftUI

enum AppTheme: String, CaseIterable {
    case basic = "Basic"
    case cyberpunk = "Cyberpunk"
    case retroWave = "Retro Wave"
    case neonNight = "Neon Night"
    case deepOcean = "Deep Ocean"

    func colors(for scheme: ColorScheme) -> ThemeColors {
        switch self {
        case .basic:
            return ThemeColors(
                primary: [Color(hex: "007AFF"), Color(hex: "2B95FF")],
                secondary: [Color(hex: "007AFF").opacity(0.2), Color(hex: "007AFF").opacity(0.1)],
                accent: Color(hex: "007AFF"),
                text: .white,
                background: scheme == .dark ? Color(.systemBackground) : .white,
                cardBackground: scheme == .dark
                    ? Color(.secondarySystemGroupedBackground) : Color(.systemGray6),
                destructive: Color(hex: "FF3B30"),
                textPrimary: scheme == .dark ? .white : Color(.label),
                textSecondary: scheme == .dark ? Color(.secondaryLabel) : Color(.secondaryLabel),
                headerBackground: [Color(hex: "007AFF"), Color(hex: "2B95FF")],
                headerOverlay: Color.white.opacity(0.1)
            )
        case .cyberpunk:
            return ThemeColors(
                primary: [Color(hex: "FF0055"), Color(hex: "00FF66")],
                secondary: [Color(hex: "00FF66").opacity(0.2), Color(hex: "FF00A2").opacity(0.1)],
                accent: Color(hex: "00FF66"),
                text: .white,
                background: scheme == .dark ? Color(hex: "0A0A0F") : Color(hex: "F8F8FF"),
                cardBackground: scheme == .dark ? Color(hex: "1A1A25") : Color(hex: "FFFFFF"),
                destructive: Color(hex: "FF3D71"),
                textPrimary: scheme == .dark ? .white : Color(hex: "1A1A25"),
                textSecondary: scheme == .dark ? Color(hex: "8F8F9E") : Color(hex: "6B6B7E"),
                headerBackground: [
                    Color(hex: "FF0055"),
                    Color(hex: "9D00FF"),
                    Color(hex: "00FF66"),
                ],
                headerOverlay: Color(hex: "00FF66").opacity(scheme == .dark ? 0.1 : 0.05)
            )
        case .retroWave:
            return ThemeColors(
                primary: [Color(hex: "FF2E6C"), Color(hex: "FF00A2")],
                secondary: [Color(hex: "00F9FF").opacity(0.2), Color(hex: "00F9FF").opacity(0.1)],
                accent: Color(hex: "00F9FF"),
                text: .white,
                background: scheme == .dark ? Color(hex: "120458") : Color(hex: "F0F0FF"),
                cardBackground: scheme == .dark ? Color(hex: "1B0B40") : Color(hex: "FFFFFF"),
                destructive: Color(hex: "FF3D71"),
                textPrimary: scheme == .dark ? .white : Color(hex: "120458"),
                textSecondary: scheme == .dark ? Color(hex: "B4A5FF") : Color(hex: "6B61A7"),
                headerBackground: [
                    Color(hex: "FF2E6C"),
                    Color(hex: "FB00FF"),
                    Color(hex: "00F9FF"),
                ],
                headerOverlay: Color(hex: "00F9FF").opacity(scheme == .dark ? 0.15 : 0.08)
            )
        case .neonNight:
            return ThemeColors(
                primary: [Color(hex: "00FF66"), Color(hex: "00FFE0")],
                secondary: [Color(hex: "FFFF00").opacity(0.2), Color(hex: "00FFE0").opacity(0.1)],
                accent: Color(hex: "FFFF00"),
                text: .white,
                background: scheme == .dark ? Color(hex: "090415") : Color(hex: "F5FFF8"),
                cardBackground: scheme == .dark ? Color(hex: "131025") : Color(hex: "FFFFFF"),
                destructive: Color(hex: "FF0055"),
                textPrimary: scheme == .dark ? .white : Color(hex: "090415"),
                textSecondary: scheme == .dark ? Color(hex: "7E7E9A") : Color(hex: "4A4A66"),
                headerBackground: [
                    Color(hex: "00FF66"),
                    Color(hex: "00FFE0"),
                    Color(hex: "FFFF00"),
                ],
                headerOverlay: Color(hex: "FFFF00").opacity(scheme == .dark ? 0.1 : 0.05)
            )
        case .deepOcean:
            return ThemeColors(
                primary: [Color(hex: "1A2980"), Color(hex: "26D0CE")],
                secondary: [Color(hex: "26D0CE").opacity(0.2), Color(hex: "26D0CE").opacity(0.1)],
                accent: Color(hex: "26D0CE"),
                text: .white,
                background: scheme == .dark ? Color(hex: "0A192F") : Color(hex: "F8FAFF"),
                cardBackground: scheme == .dark ? Color(hex: "112240") : .white,
                destructive: Color(hex: "FF647C"),
                textPrimary: scheme == .dark ? .white : Color(hex: "0A192F"),
                textSecondary: scheme == .dark ? Color(hex: "8892B0") : Color(hex: "4A5568"),
                headerBackground: [Color(hex: "1A2980"), Color(hex: "26D0CE")],
                headerOverlay: Color.white.opacity(scheme == .dark ? 0.05 : 0.02)
            )
        }
    }
}

struct ThemeColors {
    let primary: [Color]
    let secondary: [Color]
    let accent: Color
    let text: Color
    let background: Color
    let cardBackground: Color
    let destructive: Color
    let textPrimary: Color
    let textSecondary: Color
    let headerBackground: [Color]
    let headerOverlay: Color
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:  // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
