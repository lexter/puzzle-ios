import SwiftUI

private let previewMine = PuzzleState(size: 4, tiles: [5, 1, 2, 4, 9, 6, 3, 8, 13, 10, 7, 11, 0, 14, 15, 12])
private let previewRival = PuzzleState(size: 4, tiles: [1, 2, 3, 0, 4, 5, 6, 7, 8, 9, 11, 10, 12, 13, 14, 15])

/// Race-first landing that fits on one phone screen (it only scrolls in landscape or on very
/// small windows): racing a friend nearby is the hero and solo play is the quieter second option.
/// Photos are picked in the lobby or the solo game.
struct LandingScreen: View {
    let onPlay: (Players, Mode) -> Void
    let onLeaderboard: () -> Void
    @State private var mode = Mode.timeBased
    @Environment(\.palette) private var palette

    var body: some View {
        ScreenScaffold {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("SWEET & OFFLINE").font(.system(size: 12, weight: .bold)).tracking(1.8).foregroundColor(palette.secondaryText)
                            Text(appName).displayStyle(30).foregroundColor(palette.text)
                        }
                        Spacer()
                        GlassIconButton(systemImage: "trophy.fill", label: "Leaderboard", tint: palette.gold, action: onLeaderboard)
                    }

                    SegmentedControl(
                        segments: [
                            Segment(value: Mode.timeBased, label: "Time attack", systemImage: "timer"),
                            Segment(value: Mode.free, label: "Free play", systemImage: "infinity"),
                        ],
                        selected: mode
                    ) { mode = $0 }

                    RaceCard(image: Scenic.image) { onPlay(.p2p, mode) }
                    GlassButton(title: "Play solo", systemImage: "person.fill") { onPlay(.single, mode) }
                    Text("Pick your own photo in the lobby or before a solo game.")
                        .font(.system(size: 13))
                        .foregroundColor(palette.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct RaceCard: View {
    let image: CGImage
    let onFindRival: () -> Void
    @Environment(\.palette) private var palette
    @State private var pulsing = false

    var body: some View {
        GlassSurface(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 0) {
                        Circle().fill(palette.accent.opacity(pulsing ? 1 : 0.35)).frame(width: 8, height: 8)
                            .animation(.linear(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
                        Text("  Play nearby").font(.system(size: 13, weight: .semibold)).foregroundColor(palette.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.track))
                    Text("WI-FI · NO INTERNET")
                        .font(.system(size: 11, weight: .bold)).tracking(1.2)
                        .foregroundColor(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Race a friend").displayStyle(25).foregroundColor(palette.text)
                    Text("Same photo, same shuffle. First to finish wins.").font(.system(size: 15)).foregroundColor(palette.secondaryText)
                }
                HStack {
                    MiniBoard(state: previewMine, image: image, ring: palette.accent, label: "YOU", alpha: 1)
                    Spacer(minLength: 0)
                    Text("VS")
                        .displayStyle(18)
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(CandyCta.gradient))
                        .shadow(color: CandyCta.bottom, radius: 7)
                        .scaleEffect(pulsing ? 1.08 : 1)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                    Spacer(minLength: 0)
                    MiniBoard(state: previewRival, image: image, ring: palette.opponentAccent, label: "RIVAL", alpha: 0.85)
                }
                PrimaryButton(title: "Find a rival", systemImage: "wifi", action: onFindRival)
            }
            .padding(18)
        }
        .onAppear { pulsing = true }
    }
}

private struct MiniBoard: View {
    let state: PuzzleState
    let image: CGImage
    let ring: Color
    let label: String
    let alpha: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 6) {
            GlassSurface(shape: shape, solid: true) {
                BoardView(state: state, image: image, interactive: false)
                    .opacity(alpha)
                    .padding(6)
                    .frame(width: 132, height: 132)
            }
                .overlay(shape.strokeBorder(ring, lineWidth: 2.5))
                .shadow(color: ring.opacity(0.6), radius: 10)
            Text(label).font(.system(size: 13, weight: .heavy)).tracking(1).foregroundColor(ring)
        }
    }
}
