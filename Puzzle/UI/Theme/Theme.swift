import SwiftUI

extension Color {
    /// `0xAARRGGBB`, like Compose's `Color(0xFF…)`.
    init(argb: UInt32) {
        self.init(
            .sRGB,
            red: Double((argb >> 16) & 0xFF) / 255,
            green: Double((argb >> 8) & 0xFF) / 255,
            blue: Double(argb & 0xFF) / 255,
            opacity: Double((argb >> 24) & 0xFF) / 255
        )
    }

    /// Relative luminance (sRGB), as Compose's `Color.luminance()`.
    var luminance: Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let c = Double(c)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}

func resolveDark(_ appearance: Appearance, systemDark: Bool) -> Bool {
    switch appearance {
    case .light: return false
    case .dark: return true
    case .system: return systemDark
    }
}

/// "Candy Pop" palette. `accent` is the local player ("you", blueberry) and `opponentAccent`
/// is the rival (tangerine): they differ in hue and lightness so they read apart for everyone.
struct PuzzlePalette {
    let isDark: Bool
    let accent: Color
    let onAccent: Color
    let text: Color
    let secondaryText: Color
    let background: Color
    let glassTintSolid: Color
    let selectedFill: Color
    let selectedText: Color
    let opponentAccent: Color
    let track: Color
    let glowA: Color
    let glowB: Color
    let gold: Color
    let sprinkles: [Color]

    static let dark = PuzzlePalette(
        isDark: true,
        accent: Color(argb: 0xFF4FD1FF),
        onAccent: Color(argb: 0xFF06141A),
        text: Color(argb: 0xFFF4F1FF),
        secondaryText: Color(argb: 0xFFEBCFF2),
        background: Color(argb: 0xFF2A0E4F),
        glassTintSolid: Color(argb: 0xFF3B1868).opacity(0.97),
        selectedFill: Color(argb: 0xFFF4F1FF),
        selectedText: Color(argb: 0xFF4A1D3F),
        opponentAccent: Color(argb: 0xFFFF8A3D),
        track: Color.white.opacity(0.12),
        glowA: Color(argb: 0xFFFF4FA3).opacity(0.45),
        glowB: Color(argb: 0xFFEA580C).opacity(0.30),
        gold: Color(argb: 0xFFFFC94D),
        sprinkles: sprinkleColors
    )

    static let light = PuzzlePalette(
        isDark: false,
        accent: Color(argb: 0xFF0E7490),
        onAccent: .white,
        text: Color(argb: 0xFF4A1D3F),
        secondaryText: Color(argb: 0xFF7A4A63),
        background: Color(argb: 0xFFFFF1E6),
        glassTintSolid: Color.white.opacity(0.97),
        selectedFill: Color(argb: 0xFF4A1D3F),
        selectedText: .white,
        opponentAccent: Color(argb: 0xFFC2410C),
        track: Color(argb: 0xFF4A1D3F).opacity(0.08),
        glowA: Color(argb: 0xFFFF4FA3).opacity(0.22),
        glowB: Color(argb: 0xFFEA580C).opacity(0.16),
        gold: Color(argb: 0xFFB45309),
        sprinkles: Array(sprinkleColors.dropLast())
    )

    private static let sprinkleColors: [Color] = [
        Color(argb: 0xFFFF7AB6), Color(argb: 0xFF4FD1FF), Color(argb: 0xFFFFD84D), Color(argb: 0xFF7CF0B4), Color(argb: 0xFFFF8A3D), .white,
    ]
}

/// Strawberry → tangerine candy button, the same in both modes. White label passes 3:1 at 18 pt bold.
enum CandyCta {
    static let top = Color(argb: 0xFFFF7AB6)
    static let bottom = Color(argb: 0xFFFF6A3D)
    static let base = Color(argb: 0xFFC23A1C)
    static var gradient: LinearGradient { LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom) }
    /// Text gradient for big celebratory titles.
    static var titleGradient: LinearGradient {
        LinearGradient(colors: [Color(argb: 0xFF4FD1FF), Color(argb: 0xFFFFB3D9), Color(argb: 0xFFFF8A3D)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = PuzzlePalette.light
}

extension EnvironmentValues {
    var palette: PuzzlePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Font {
    /// Chunky display face for titles and big numbers.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
}

extension View {
    /// Display style: heavy weight, slightly tightened.
    @ViewBuilder
    func displayStyle(_ size: CGFloat) -> some View {
        if #available(iOS 16.0, *) { font(.display(size)).tracking(-0.3) } else { font(.display(size)) }
    }

    /// Fixed-width digits so numbers don't jitter.
    func tabularNumbers(_ size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight).monospacedDigit())
    }

    /// Fills text with a gradient.
    func gradientForeground<S: ShapeStyle>(_ style: S) -> some View {
        overlay(style).mask(self)
    }
}

/// Resolves the palette from the saved appearance and the system setting.
struct PuzzleTheme<Content: View>: View {
    let appearance: Appearance
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = resolveDark(appearance, systemDark: colorScheme == .dark)
        let palette = isDark ? PuzzlePalette.dark : PuzzlePalette.light
        content
            .environment(\.palette, palette)
            .environment(\.colorScheme, isDark ? .dark : .light)
            .foregroundColor(palette.text)
            .tint(palette.accent)
    }
}
