import SwiftUI

/// 48 pt rounded-square frosted button with an icon (back, settings, leaderboard).
struct GlassIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color?
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            GlassSurface(cornerRadius: 16, interactive: true) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(tint ?? palette.text)
                    .frame(width: 48, height: 48)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Glossy candy button (Play, Find a rival, Start, Apply): strawberry → tangerine face with a
/// shine strip, sitting on a darker base that it sinks into while pressed.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(CandyButtonStyle(systemImage: systemImage))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

private struct CandyButtonStyle: ButtonStyle {
    static let face: CGFloat = 56
    static let depth: CGFloat = 5
    let systemImage: String?

    func makeBody(configuration: Configuration) -> some View {
        let lift = configuration.isPressed ? 1 : Self.depth
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack(alignment: .top) {
            shape.fill(CandyCta.base)
                .frame(height: Self.face)
                .offset(y: Self.depth)
            ZStack {
                shape.fill(CandyCta.gradient)
                GeometryReader { geo in
                    Capsule()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: geo.size.width * 0.88, height: 18)
                        .position(x: geo.size.width / 2, y: 4 + 9)
                }
                HStack(spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 19, weight: .bold))
                    }
                    configuration.label.font(.system(size: 18, weight: .heavy))
                }
                .foregroundColor(.white)
            }
            .frame(height: Self.face)
            .offset(y: Self.depth - lift)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.face + Self.depth, alignment: .top)
        .contentShape(Rectangle())
    }
}

/// Secondary frosted button ("Home", "Play solo", "Back to lobby").
struct GlassButton: View {
    let title: String
    var systemImage: String?
    var iconTint: Color?
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            GlassSurface(cornerRadius: 20, interactive: true) {
                HStack(spacing: 8) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 17, weight: .semibold)).foregroundColor(iconTint ?? palette.text)
                    }
                    Text(title).font(.system(size: 16, weight: .semibold)).foregroundColor(palette.text)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
        }
        .buttonStyle(.plain)
    }
}

struct Segment<T: Hashable>: Identifiable {
    let value: T
    let label: String
    var systemImage: String?
    var id: T { value }
}

/// Segmented control (Time attack/Free play, Join/Host, Light/Dark/System, grid tabs).
struct SegmentedControl<T: Hashable>: View {
    let segments: [Segment<T>]
    let selected: T
    var height: CGFloat = 46
    var enabled = true
    let onSelect: (T) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        GlassSurface(cornerRadius: 20) {
            HStack(spacing: 4) {
                ForEach(segments) { segment in
                    let isSelected = segment.value == selected
                    let color = isSelected ? palette.selectedText : palette.text
                    Button { onSelect(segment.value) } label: {
                        HStack(spacing: 6) {
                            if let icon = segment.systemImage {
                                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                            }
                            Text(segment.label)
                                .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundColor(color)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? palette.selectedFill : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .opacity(enabled || isSelected ? 1 : 0.45)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Stopwatch pill shown at the top of time-based games.
struct TimerPill: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        GlassSurface(shape: shape) {
            HStack(spacing: 8) {
                Image(systemName: "timer").font(.system(size: 16, weight: .semibold)).foregroundColor(palette.accent)
                Text(text).font(.system(size: 21, weight: .heavy).monospacedDigit()).foregroundColor(palette.text)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
        }
        .overlay(shape.strokeBorder(palette.accent.opacity(0.6), lineWidth: 1.5))
    }
}

struct SectionLabel: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .bold))
            .tracking(1.4)
            .foregroundColor(palette.secondaryText)
            .padding(.horizontal, 6)
    }
}

/// Race bar: you fill from the left, the rival from the right, both toward a finish line in
/// the middle. Each side reaching the middle means that player's picture is complete.
struct TugOfWar: View {
    let youFraction: Double
    let rivalFraction: Double
    let youLabel: String
    let rivalLabel: String
    @Environment(\.palette) private var palette

    var body: some View {
        let you = palette.accent
        let rival = palette.opponentAccent
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text(youLabel).tabularNumbers(13, weight: .bold).foregroundColor(you).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("FINISH").font(.system(size: 12, weight: .bold)).tracking(1.6).foregroundColor(palette.secondaryText)
                Text(rivalLabel).tabularNumbers(13, weight: .bold).foregroundColor(rival).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack {
                    HStack(spacing: 0) {
                        ZStack(alignment: .leading) {
                            Color.clear
                            RoundedRectangle(cornerRadius: 7)
                                .fill(LinearGradient(colors: [you.opacity(0.45), you], startPoint: .leading, endPoint: .trailing))
                                .frame(width: half * youFraction.clamped(to: 0...1))
                        }
                        ZStack(alignment: .trailing) {
                            Color.clear
                            RoundedRectangle(cornerRadius: 7)
                                .fill(LinearGradient(colors: [rival, rival.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: half * rivalFraction.clamped(to: 0...1))
                        }
                    }
                    Rectangle().fill(palette.text).frame(width: 3)
                }
            }
            .frame(height: 14)
            .background(palette.track)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Round initial badge for a player.
struct Avatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 42
    var glow = false

    var body: some View {
        let initial = name.first.map { String($0).uppercased() } ?? "?"
        Text(initial)
            .displayStyle(size * 0.4)
            .foregroundColor(color.luminance < 0.35 ? .white : Color(argb: 0xFF1F0D1A))
            .frame(width: size, height: size)
            .background(Circle().fill(color))
            .shadow(color: glow ? color : .clear, radius: glow ? 10 : 0)
    }
}
