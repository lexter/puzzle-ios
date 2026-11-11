import SwiftUI

/// Full-screen candy backdrop: base color, two soft color glows and scattered sprinkles.
/// The candy style keeps the backdrop calm so the board itself stays the hero.
struct GlassBackdrop: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.background))
            glow(&context, color: palette.glowA, center: CGPoint(x: size.width * 0.1, y: size.height * 0.08), radius: size.width * 0.75)
            glow(&context, color: palette.glowB, center: CGPoint(x: size.width * 1.0, y: size.height * 0.55), radius: size.width * 0.8)
            let w: CGFloat = 14
            let h: CGFloat = 5
            for sprinkle in Self.sprinkles {
                let center = CGPoint(x: CGFloat(sprinkle.x) * size.width, y: CGFloat(sprinkle.y) * size.height)
                var piece = context
                piece.translateBy(x: center.x, y: center.y)
                piece.rotate(by: .degrees(Double(sprinkle.angle)))
                let color = palette.sprinkles[sprinkle.colorIndex % palette.sprinkles.count].opacity(palette.isDark ? 0.55 : 0.45)
                piece.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2), with: .color(color))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ context: inout GraphicsContext, color: Color, center: CGPoint, radius: CGFloat) {
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: center, startRadius: 0, endRadius: radius)
        )
    }

    private struct Sprinkle {
        let x: Float, y: Float, angle: Float, colorIndex: Int
    }

    private static let sprinkles: [Sprinkle] = {
        var random = KotlinRandom(seed: 7)
        return (0..<26).map { _ in
            let x = random.nextFloat()
            let y = random.nextFloat()
            let angle = random.nextFloat() * 180
            return Sprinkle(x: x, y: y, angle: angle, colorIndex: random.nextInt(until: 6))
        }
    }()
}

/// Panel used for every bar, card, chip and sheet, rendered with the system's glass:
/// Liquid Glass (`glassEffect`) on iOS 26 and later, system materials on earlier versions.
///
/// - `solid`: floating surfaces over the board (dialogs, countdown, pause) get a thicker,
///   tinted glass so their text stays readable.
/// - `interactive`: tappable surfaces react to touch (system press highlight and shimmer).
/// - `tint`: colors the glass, e.g. a selected chip.
struct GlassSurface<S: InsettableShape, Content: View>: View {
    var shape: S
    var solid = false
    var interactive = false
    var tint: Color?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(solid ? Material.thick : Material.ultraThin, in: shape)
                .background(shape.fill(fallbackTint ?? .clear))
                .clipShape(shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint = tint ?? (solid ? palette.glassTintSolid.opacity(0.55) : nil) { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    private var fallbackTint: Color? { tint ?? (solid ? palette.glassTintSolid.opacity(0.55) : nil) }
}

extension GlassSurface where S == RoundedRectangle {
    init(
        cornerRadius: CGFloat = 28,
        solid: Bool = false,
        interactive: Bool = false,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            solid: solid,
            interactive: interactive,
            tint: tint,
            content: content
        )
    }
}

/// Backdrop + safe-area padding shared by every screen.
struct ScreenScaffold<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            GlassBackdrop()
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// A vertical scroll view that is only as tall as its content, up to the space offered.
struct WrappingScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content.background(
                GeometryReader { geo in Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height) }
            )
        }
        .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
