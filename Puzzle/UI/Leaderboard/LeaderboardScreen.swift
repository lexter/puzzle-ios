import SwiftUI

let emptyLeaderboard = "No times yet. Finish a time-based game to set one."

@MainActor
final class LeaderboardModel: ObservableObject, ScreenModel {
    private let scores: ScoreStore
    @Published private(set) var selectedSize = PuzzleState.defaultSize
    @Published private(set) var rows: [Score] = []

    init(scores: ScoreStore) {
        self.scores = scores
        rows = scores.topTen(selectedSize)
    }

    func select(_ size: Int) {
        selectedSize = size.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        rows = scores.topTen(selectedSize)
    }
}

private let medals = [Color(argb: 0xFFFFD66B), Color(argb: 0xFFD9E1EC), Color(argb: 0xFFF2C2A0)]

struct LeaderboardScreen: View {
    @ObservedObject var model: LeaderboardModel
    let onBack: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let selected = model.selectedSize
        ScreenScaffold {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        GlassIconButton(systemImage: "arrow.left", label: "Back", action: onBack)
                        Text("Leaderboard").displayStyle(24).foregroundColor(palette.text)
                    }
                    SegmentedControl(
                        segments: PuzzleState.sizes.map { Segment(value: $0, label: "\($0)×\($0)") },
                        selected: selected,
                        height: 44,
                        onSelect: model.select
                    )
                    Text("Top 10 · \(selected)×\(selected) · time-based")
                        .font(.system(size: 13)).foregroundColor(palette.secondaryText).padding(.horizontal, 8)
                    GlassSurface(cornerRadius: 24) {
                        if model.rows.isEmpty {
                            Text(emptyLeaderboard)
                                .foregroundColor(palette.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(model.rows.enumerated()), id: \.offset) { index, score in
                                    ScoreRow(rank: index + 1, score: score)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ScoreRow: View {
    let rank: Int
    let score: Score
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(rank <= 3 ? Color(argb: 0xFF12203A) : palette.text)
                .frame(width: 28, height: 28)
                .background(Circle().fill(rank <= medals.count ? medals[rank - 1] : palette.track))
            Text(formatElapsed(score.timeMs)).tabularNumbers(18).foregroundColor(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(score.moves) moves").tabularNumbers(14, weight: .regular).foregroundColor(palette.secondaryText)
                .frame(width: 84, alignment: .leading)
            Text(shortDate(score.playedAt)).font(.system(size: 13)).foregroundColor(palette.secondaryText)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
    }
}

/// "Nov 11": English month abbreviation and day, in the device's time zone.
func shortDate(_ epochMs: Int64) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
    let parts = Calendar.current.dateComponents([.month, .day], from: date)
    let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return "\(months[(parts.month ?? 1) - 1]) \(parts.day ?? 1)"
}
