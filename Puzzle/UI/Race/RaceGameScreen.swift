import SwiftUI

let mirrorAlpha = 0.7
private let mirrorMaxSidePanel: CGFloat = 200
private let rivalCloseTiles = 4
private let mirrorWidthCompact: CGFloat = 100

/// Decodes the host's photo once per match picture.
@MainActor
final class RaceImageCache: ObservableObject {
    private var bytes: Data?
    private var image: CGImage?

    func image(for bytes: Data?) -> CGImage? {
        guard let bytes else { return nil }
        if bytes != self.bytes {
            self.bytes = bytes
            image = try? PuzzleImage.prepare(bytes).get()
        }
        return image
    }
}

/// Peer-to-peer race. `onLeave` must end the match (`MatchHub.end`) and navigate away.
struct RaceGameScreen: View {
    @ObservedObject var controller: MatchController
    @ObservedObject var settings: SettingsRepository
    let onLeave: () -> Void
    @StateObject private var images = RaceImageCache()
    @State private var showSettings = false
    @State private var elapsed: Int64 = 0
    @State private var countdown: Int64 = 0
    @State private var drag = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var mirrorSize = CGSize.zero
    @Environment(\.palette) private var palette

    var body: some View {
        let match = controller.state
        let image = images.image(for: match.imageBytes) ?? Scenic.image
        let config = match.config
        let grid = config?.grid ?? PuzzleState.defaultSize
        let peer = match.peerName ?? "Opponent"
        let timed = config?.mode != .free
        let myBoard = match.me ?? PuzzleEngine.solved(grid)
        let theirBoard = match.opponent ?? PuzzleEngine.solved(grid)
        let result = match.result
        let raceStarted = match.raceStartedAt != nil && match.me?.isSolved == false

        ZStack {
            ScreenScaffold {
                GeometryReader { geo in
                    let layout = layoutMode(width: geo.size.width, height: geo.size.height)
                    VStack(spacing: 14) {
                        GameTopBar(onBack: onLeave, timerText: timed ? formatElapsed(elapsed) : nil, onSettings: { showSettings = true }, backLabel: "Leave match")
                        StatusLine(peer: peer, match: match, grid: grid)

                        if layout == .compact {
                            VStack(spacing: 14) {
                                // The opponent's board floats over the top-right corner of mine at 70% opacity.
                                GeometryReader { area in
                                    ZStack(alignment: .topTrailing) {
                                        myBoardView(myBoard, image: image, match: match)
                                            .padding(.top, 8)
                                            .frame(width: area.size.width, height: area.size.height, alignment: .top)
                                        // Small, draggable copy of the rival's board, starting over the top-right corner.
                                        OpponentMirror(board: theirBoard, image: image, name: peer, draggable: true)
                                            .frame(width: mirrorWidthCompact)
                                            .background(GeometryReader { mirror in
                                                Color.clear
                                                    .onAppear { mirrorSize = mirror.size }
                                                    .onChange(of: mirror.size) { mirrorSize = $0 }
                                            })
                                            .offset(drag)
                                            .gesture(mirrorDrag(in: area.size))
                                    }
                                }
                                .frame(maxHeight: boardAreaHeight(width: min(geo.size.width, 640)))
                                side(myBoard: myBoard, theirBoard: theirBoard, peer: peer, match: match)
                            }
                            .frame(maxWidth: 640)
                        } else {
                            HStack(spacing: 28) {
                                myBoardView(myBoard, image: image, match: match).frame(maxWidth: .infinity, maxHeight: .infinity)
                                ScrollView {
                                    VStack(spacing: 16) {
                                        OpponentMirror(board: theirBoard, image: image, name: peer).frame(maxWidth: mirrorMaxSidePanel)
                                        side(myBoard: myBoard, theirBoard: theirBoard, peer: peer, match: match)
                                    }
                                }
                                .frame(width: 360)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .overlay(match.phase == .countdown ? VsCountdown(remainingMs: countdown, peer: peer) : nil)
                .overlay(
                    MessageToast(
                        text: noticeText(match.notice, peer: peer),
                        actionLabel: match.notice == .rematchRequested ? "Rematch" : nil,
                        onAction: { controller.rematch(); controller.dismissNotice() },
                        onDismiss: controller.dismissNotice
                    )
                )
            }

            ResultCard(
                visible: match.phase == .finished && result != nil,
                title: result?.iWon == true ? "YOU WIN!" : "\(peer) won",
                lines: [
                    result.flatMap { timed ? "Winning time \(formatElapsed($0.winnerTimeMs))" : nil },
                    "\(myBoard.moves) moves · \(grid)×\(grid)",
                ].compactMap { $0 },
                highlight: nil,
                primaryLabel: controller.role == .host ? "Rematch" : "Ask for rematch",
                onPrimary: controller.rematch,
                secondaryLabel: "Leave",
                onSecondary: onLeave,
                celebrate: result?.iWon == true
            )

            ResultCard(
                visible: match.phase == .lost,
                title: lostTitle(match.lostReason, peer: peer),
                lines: [match.lostReason == .versionMismatch ? "Both players need the same app version." : "This race can't continue."],
                highlight: nil,
                primaryLabel: raceStarted ? "Keep playing solo" : "Back to lobby",
                onPrimary: raceStarted ? controller.continueSolo : onLeave,
                secondaryLabel: raceStarted ? "Back to lobby" : "Home",
                onSecondary: onLeave
            )

            ResultCard(
                visible: match.phase == .solo && match.me?.isSolved == true,
                title: "Solved!",
                lines: ["Unranked · \(formatElapsed(match.mySolvedMs ?? 0)) · \(myBoard.moves) moves"],
                highlight: nil,
                primaryLabel: "Back to lobby",
                onPrimary: onLeave,
                secondaryLabel: "Home",
                onSecondary: onLeave
            )

            SettingsSheet(
                visible: showSettings,
                gridSize: grid,
                appearance: settings.appearance,
                gridLocked: controller.role != .host || match.phase == .racing || match.phase == .countdown,
                onApply: { newGrid, newAppearance in
                    showSettings = false
                    if newAppearance != settings.appearance { settings.setAppearance(newAppearance) }
                    let current = controller.state
                    if controller.role == .host, let config = current.config, newGrid != grid,
                       current.phase == .configured || current.phase == .finished {
                        controller.configure(grid: newGrid, mode: config.mode, imageBytes: current.imageBytes)
                    }
                },
                onDismiss: { showSettings = false }
            )
        }
        .task(id: StopwatchKey(phase: match.phase, solvedMs: match.mySolvedMs)) {
            elapsed = 0
            while (controller.state.phase == .racing || controller.state.phase == .solo) && controller.state.mySolvedMs == nil && !Task.isCancelled {
                elapsed = controller.elapsedNow()
                await sleep(ms: 100)
            }
            elapsed = controller.state.mySolvedMs ?? controller.elapsedNow()
        }
        .task(id: match.phase) {
            countdown = 0
            while controller.state.phase == .countdown && !Task.isCancelled {
                countdown = controller.millisUntilStart()
                await sleep(ms: 50)
            }
            countdown = 0
        }
        .onChange(of: match.phase) { phase in
            if phase == .finished && controller.state.result?.iWon == true { Haptics.success() }
        }
        .task(id: match.notice) {
            guard match.notice != nil else { return }
            await sleep(ms: 4_000)
            if !Task.isCancelled { controller.dismissNotice() }
        }
    }

    private struct StopwatchKey: Equatable {
        let phase: MatchPhase
        let solvedMs: Int64?
    }

    /// Height of the compact board area: the board is as wide as the column (plus the top inset).
    private func boardAreaHeight(width: CGFloat) -> CGFloat { width + 8 }

    private func mirrorDrag(in bounds: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let maxLeft = max(bounds.width - mirrorSize.width, 0)
                let maxDown = max(bounds.height - mirrorSize.height, 0)
                drag = CGSize(
                    width: (dragStart.width + value.translation.width).clamped(to: -maxLeft...0),
                    height: (dragStart.height + value.translation.height).clamped(to: 0...maxDown)
                )
            }
            .onEnded { _ in dragStart = drag }
    }

    private func myBoardView(_ board: PuzzleState, image: CGImage, match: MatchSnapshot) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return GlassSurface(shape: shape) {
            BoardView(
                state: board,
                image: image,
                interactive: (match.phase == .racing || match.phase == .solo) && match.mySolvedMs == nil
            ) { id in
                Haptics.tap()
                controller.tapTile(id)
            }
            .padding(12)
        }
        .overlay(shape.strokeBorder(palette.accent, lineWidth: 3))
        .shadow(color: palette.accent.opacity(0.6), radius: 16)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func side(myBoard: PuzzleState, theirBoard: PuzzleState, peer: String, match: MatchSnapshot) -> some View {
        RaceProgress(me: myBoard, opponent: theirBoard, peer: peer)
        if match.phase == .racing && match.mySolvedMs == nil {
            RivalCloseBanner(me: myBoard, opponent: theirBoard, peer: peer)
        }
        PreRaceControls(role: controller.role, match: match, onStart: controller.startRace)
    }

    private func noticeText(_ notice: MatchNotice?, peer: String) -> String? {
        switch notice {
        case .imageFallback: return "Couldn't send the photo, so you're racing on the scenic picture."
        case .rematchRequested: return "\(peer) wants a rematch."
        case nil: return nil
        }
    }

    private func lostTitle(_ reason: LossReason?, peer: String) -> String {
        switch reason {
        case .peerLeft: return "\(peer) left"
        case .versionMismatch: return "Different app versions"
        default: return "Connection lost"
        }
    }
}

private struct StatusLine: View {
    let peer: String
    let match: MatchSnapshot
    let grid: Int
    @Environment(\.palette) private var palette

    var body: some View {
        let connected = match.phase != .lost && match.phase != .solo
        HStack(spacing: 0) {
            Circle().fill(connected ? Color(argb: 0xFF22C55E) : Color(argb: 0xFFEF4444)).frame(width: 8, height: 8)
            Text(connected ? "  Connected · \(peer)" : "  Offline · solo").font(.system(size: 14)).foregroundColor(palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(grid)×\(grid) · Moves \(match.me?.moves ?? 0)").tabularNumbers(14, weight: .regular).foregroundColor(palette.secondaryText)
        }
        .padding(.horizontal, 6)
    }
}

/// The other player's live board, 70% opaque and not tappable.
struct OpponentMirror: View {
    let board: PuzzleState
    let image: CGImage
    let name: String
    var draggable = false
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        GlassSurface(shape: shape, solid: true) {
            VStack(spacing: 4) {
                if draggable {
                    RoundedRectangle(cornerRadius: 2).fill(palette.text.opacity(0.6)).frame(width: 28, height: 4)
                }
                BoardView(state: board, image: image, interactive: false)
                HStack {
                    Text(name).font(.system(size: 12, weight: .heavy)).foregroundColor(palette.opponentAccent).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(board.tilesInPlace)/\(board.tileCount)").tabularNumbers(12).foregroundColor(palette.text)
                }
            }
            .padding(6)
        }
        .overlay(shape.strokeBorder(palette.opponentAccent, lineWidth: 3))
        .opacity(mirrorAlpha)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(draggable ? "\(name)'s board, live. Drag to move it." : "\(name)'s board, live")
    }
}

private struct RaceProgress: View {
    let me: PuzzleState
    let opponent: PuzzleState
    let peer: String

    var body: some View {
        GlassSurface(cornerRadius: 22) {
            TugOfWar(
                youFraction: Double(me.tilesInPlace) / Double(me.tileCount),
                rivalFraction: Double(opponent.tilesInPlace) / Double(opponent.tileCount),
                youLabel: "YOU · \(me.tilesInPlace)/\(me.tileCount)",
                rivalLabel: "\(peer.uppercased()) · \(opponent.tilesInPlace)/\(opponent.tileCount)"
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

/// Nudge shown when the rival is ahead and close to finishing.
private struct RivalCloseBanner: View {
    let me: PuzzleState
    let opponent: PuzzleState
    let peer: String
    @Environment(\.palette) private var palette

    var body: some View {
        let left = opponent.tileCount - opponent.tilesInPlace
        if left != 0 && left <= rivalCloseTiles && opponent.tilesInPlace > me.tilesInPlace {
            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
            HStack(spacing: 0) {
                Image(systemName: "bolt.fill").font(.system(size: 16)).foregroundColor(palette.opponentAccent)
                Text("  \(peer) is \(left) \(left == 1 ? "tile" : "tiles") from done. Speed up!")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(palette.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(shape.fill(palette.opponentAccent.opacity(0.16)))
            .overlay(shape.strokeBorder(palette.opponentAccent.opacity(0.55), lineWidth: 1))
            .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private struct PreRaceControls: View {
    let role: Role
    let match: MatchSnapshot
    let onStart: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        if match.phase == .configured {
            if role == .host {
                PrimaryButton(title: "Start race · 3-2-1", enabled: match.peerReady, action: onStart)
            } else {
                Text("Waiting for the host to start…").font(.system(size: 14)).foregroundColor(palette.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Full-screen VS splash with the 3-2-1 in the middle.
private struct VsCountdown: View {
    let remainingMs: Int64
    let peer: String
    @Environment(\.palette) private var palette

    var body: some View {
        let seconds = max((remainingMs + 999) / 1000, 1)
        let pop = remainingMs % 1000 > 700
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            HStack(spacing: 12) {
                Avatar(name: "You", color: palette.accent, size: 64, glow: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("YOU").displayStyle(26).foregroundColor(palette.accent)
                    Text("Same photo · same shuffle").font(.system(size: 13)).foregroundColor(.white)
                }
            }
            .padding(.top, 80)
            .padding(.leading, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Text("\(seconds)")
                .displayStyle(88)
                .gradientForeground(LinearGradient(colors: [palette.accent, palette.opponentAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(pop ? 1.25 : 1)
                .animation(.spring(), value: pop)
                .frame(width: 170, height: 170)
                .background(Circle().fill(palette.background))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                .shadow(color: CandyCta.top, radius: 20)

            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(peer.uppercased()).displayStyle(26).foregroundColor(palette.opponentAccent).lineLimit(1)
                    Text("First to finish wins").font(.system(size: 13)).foregroundColor(.white)
                }
                Avatar(name: peer, color: palette.opponentAccent, size: 64, glow: true)
            }
            .padding(.bottom, 120)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
