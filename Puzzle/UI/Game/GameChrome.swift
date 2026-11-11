import SwiftUI

/// Back · stopwatch (time-based only) · settings.
struct GameTopBar: View {
    let onBack: () -> Void
    let timerText: String?
    let onSettings: () -> Void
    var backLabel = "Back"

    var body: some View {
        HStack {
            GlassIconButton(systemImage: "arrow.left", label: backLabel, action: onBack)
            ZStack {
                if let timerText { TimerPill(text: timerText) }
            }
            .frame(maxWidth: .infinity)
            GlassIconButton(systemImage: "gearshape.fill", label: "Game settings", action: onSettings)
        }
    }
}

/// Picture source chip (Scenic / Camera / Gallery).
struct PictureChip: View {
    let systemImage: String
    let label: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: action) {
            GlassSurface(shape: shape) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selected ? palette.accent : palette.text)
                    Text(label).font(.system(size: 13, weight: selected ? .semibold : .medium)).foregroundColor(palette.text)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
            }
            .overlay(shape.strokeBorder(selected ? palette.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct PictureRow: View {
    let customSelected: Bool
    let cameraAvailable: Bool
    let onScenic: () -> Void
    let onCamera: () -> Void
    let onGallery: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Picture")
            HStack(spacing: 10) {
                PictureChip(systemImage: "photo", label: "Scenic", selected: !customSelected, enabled: true, action: onScenic)
                PictureChip(systemImage: "camera.fill", label: "Camera", selected: false, enabled: cameraAvailable, action: onCamera)
                PictureChip(systemImage: "photo.on.rectangle", label: "Gallery", selected: customSelected, enabled: true, action: onGallery)
            }
        }
    }
}

/// Dimmed full-screen layer that hosts a bottom sheet or a centered card.
struct Overlay<Content: View>: View {
    let visible: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            if visible {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onDismiss?() }
                    .transition(.opacity)
                content
            }
        }
        .animation(.easeInOut(duration: 0.25), value: visible)
    }
}

let gridLockedNote = "Only the host can change this."

struct SettingsSheet: View {
    let visible: Bool
    let gridSize: Int
    let appearance: Appearance
    let gridLocked: Bool
    let onApply: (Int, Appearance) -> Void
    let onDismiss: () -> Void

    var body: some View {
        Overlay(visible: visible, onDismiss: onDismiss) {
            SettingsPanel(gridSize: gridSize, appearance: appearance, gridLocked: gridLocked, onApply: onApply)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom))
        }
    }
}

private struct SettingsPanel: View {
    let gridLocked: Bool
    let onApply: (Int, Appearance) -> Void
    @State private var pickedGrid: Int
    @State private var pickedAppearance: Appearance
    @Environment(\.palette) private var palette

    init(gridSize: Int, appearance: Appearance, gridLocked: Bool, onApply: @escaping (Int, Appearance) -> Void) {
        self.gridLocked = gridLocked
        self.onApply = onApply
        _pickedGrid = State(initialValue: gridSize)
        _pickedAppearance = State(initialValue: appearance)
    }

    var body: some View {
        GlassSurface(cornerRadius: 34, solid: true) {
            WrappingScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Capsule().fill(palette.track).frame(width: 40, height: 5).frame(maxWidth: .infinity)
                    Text("Game settings").displayStyle(22).foregroundColor(palette.text)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Puzzle size").font(.system(size: 14, weight: .semibold)).foregroundColor(palette.secondaryText)
                            Spacer()
                            Text("\(pickedGrid)×\(pickedGrid) · \(pickedGrid * pickedGrid - 1) tiles").font(.system(size: 14)).foregroundColor(palette.secondaryText)
                        }
                        ForEach(Array(stride(from: PuzzleState.minSize, through: PuzzleState.maxSize, by: 4)), id: \.self) { start in
                            HStack(spacing: 8) {
                                ForEach(start..<(start + 4), id: \.self) { n in
                                    if n <= PuzzleState.maxSize {
                                        SizePill(n: n, selected: n == pickedGrid, enabled: !gridLocked) { pickedGrid = n }
                                    } else {
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                    }
                                }
                            }
                        }
                        if gridLocked {
                            Text(gridLockedNote).font(.system(size: 13)).foregroundColor(palette.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Appearance").font(.system(size: 14, weight: .semibold)).foregroundColor(palette.secondaryText)
                        SegmentedControl(
                            segments: [
                                Segment(value: Appearance.light, label: "Light", systemImage: "sun.max.fill"),
                                Segment(value: Appearance.dark, label: "Dark", systemImage: "moon.fill"),
                                Segment(value: Appearance.system, label: "System", systemImage: "iphone"),
                            ],
                            selected: pickedAppearance,
                            height: 46
                        ) { pickedAppearance = $0 }
                    }

                    if !gridLocked {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill").font(.system(size: 16)).foregroundColor(palette.secondaryText)
                            Text("Changing size reshuffles the board and resets the timer.").font(.system(size: 13)).foregroundColor(palette.secondaryText)
                        }
                    }
                    PrimaryButton(title: "Apply") { onApply(pickedGrid, pickedAppearance) }
                }
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 24, trailing: 20))
            }
        }
        .frame(maxWidth: 560)
        .padding(8)
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game settings")
    }
}

private struct SizePill: View {
    let n: Int
    let selected: Bool
    let enabled: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text("\(n)×\(n)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(selected ? palette.onAccent : palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(selected ? palette.accent : palette.track))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || selected ? 1 : 0.45)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Result card. `title` e.g. "Solved!", "You win!", "Mia won".
struct ResultCard: View {
    let visible: Bool
    let title: String
    let lines: [String]
    let highlight: String?
    let primaryLabel: String
    let onPrimary: () -> Void
    let secondaryLabel: String
    let onSecondary: () -> Void
    var celebrate = false
    @Environment(\.palette) private var palette

    var body: some View {
        Overlay(visible: visible) {
            ZStack {
                if celebrate { Confetti().ignoresSafeArea().allowsHitTesting(false) }
                GlassSurface(cornerRadius: 30, solid: true) {
                    VStack(spacing: 12) {
                        if celebrate {
                            Text(title).displayStyle(40).multilineTextAlignment(.center).gradientForeground(CandyCta.titleGradient)
                        } else {
                            Text(title).displayStyle(28).foregroundColor(palette.text).multilineTextAlignment(.center)
                        }
                        ForEach(lines, id: \.self) { line in
                            Text(line).font(.system(size: 17)).foregroundColor(palette.secondaryText).multilineTextAlignment(.center)
                        }
                        if let highlight {
                            Text(highlight).font(.system(size: 16, weight: .bold)).foregroundColor(palette.accent)
                        }
                        Spacer().frame(height: 4)
                        PrimaryButton(title: primaryLabel, action: onPrimary)
                        GlassButton(title: secondaryLabel, action: onSecondary)
                    }
                    .padding(24)
                }
                .frame(maxWidth: 420)
                .padding(24)
            }
        }
    }
}

/// Short message at the bottom with an optional action.
struct MessageToast: View {
    let text: String?
    var actionLabel: String?
    var onAction: () -> Void = {}
    let onDismiss: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            if let text {
                GlassSurface(cornerRadius: 18, solid: true) {
                    HStack(spacing: 12) {
                        Text(text).font(.system(size: 14)).foregroundColor(palette.text)
                        if let actionLabel {
                            Button(action: onAction) {
                                Text(actionLabel).font(.system(size: 14, weight: .bold)).foregroundColor(palette.accent).padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: 480)
                .onTapGesture(perform: onDismiss)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 90)
    }
}

/// Falling candy-colored confetti, drawn behind the win card.
struct Confetti: View {
    private static let count = 36
    private static let loopSeconds = 4.0
    @Environment(\.palette) private var palette
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.loopSeconds) / Self.loopSeconds
                for piece in Self.pieces {
                    let t = (time * piece.speed + piece.phase).truncatingRemainder(dividingBy: 1)
                    let x = piece.x * size.width + sin(t * 6.28 + piece.phase * 10) * 18
                    let y = -20 + t * (size.height + 40)
                    var drawing = context
                    drawing.translateBy(x: x, y: y)
                    drawing.rotate(by: .degrees(t * 540 + piece.phase * 360))
                    let width: CGFloat = piece.colorIndex % 2 == 0 ? 8 : 6
                    let height: CGFloat = piece.colorIndex % 3 == 0 ? 14 : 9
                    let color = palette.sprinkles[piece.colorIndex % palette.sprinkles.count]
                    drawing.fill(Path(CGRect(x: -4, y: -6, width: width, height: height)), with: .color(color))
                }
            }
        }
    }

    private struct Piece {
        let x: Double, phase: Double, speed: Double, colorIndex: Int
    }

    private static let pieces: [Piece] = (0..<count).map { index in
        var random = KotlinRandom(seed: index * 31 + 7)
        let x = Double(random.nextFloat())
        let phase = Double(random.nextFloat())
        let speed = 0.7 + Double(random.nextFloat()) * 0.6
        return Piece(x: x, phase: phase, speed: speed, colorIndex: index)
    }
}
