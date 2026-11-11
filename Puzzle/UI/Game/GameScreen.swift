import SwiftUI

private let timerRefreshMs: Int64 = 100
private let messageMs: Int64 = 4_000

struct GameScreen: View {
    @ObservedObject var model: GameModel
    @ObservedObject var settings: SettingsRepository
    let onBack: () -> Void
    let onHome: () -> Void
    @State private var showSettings = false
    @State private var elapsed: Int64 = 0
    @Environment(\.palette) private var palette
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let image = model.customImage ?? Scenic.image
        ZStack {
            ScreenScaffold {
                GeometryReader { geo in
                    let layout = layoutMode(width: geo.size.width, height: geo.size.height)
                    let timerText = model.mode == .timeBased ? formatElapsed(elapsed) : nil
                    VStack(spacing: 16) {
                        GameTopBar(onBack: onBack, timerText: timerText, onSettings: { showSettings = true })
                        if layout == .compact {
                            VStack(spacing: 16) {
                                // The board takes the leftover height and sits centred in it.
                                board(image).frame(maxWidth: .infinity, maxHeight: .infinity)
                                controls
                            }
                            .frame(maxWidth: 640)
                        } else {
                            HStack(spacing: 28) {
                                board(image).frame(maxWidth: .infinity, maxHeight: .infinity)
                                ScrollView { VStack(alignment: .leading, spacing: 16) { controls } }
                                    .frame(width: 360)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                }
                .overlay(model.loadingPhoto ? ProgressView() : nil)
                .overlay(
                    MessageToast(
                        text: model.message?.text,
                        actionLabel: model.message == .cameraDenied ? "Settings" : nil,
                        onAction: openAppSettings,
                        onDismiss: model.dismissMessage
                    )
                )
            }

            ResultCard(
                visible: model.phase == .won,
                title: "Solved!",
                lines: [
                    model.mode == .timeBased ? "Time \(formatElapsed(model.elapsedMs))" : nil,
                    "\(model.puzzle.moves) moves · \(model.puzzle.size)×\(model.puzzle.size)",
                ].compactMap { $0 },
                highlight: model.newBest ? "New best!" : nil,
                primaryLabel: "Play again",
                onPrimary: model.playAgain,
                secondaryLabel: "Home",
                onSecondary: onHome,
                celebrate: true
            )

            SettingsSheet(
                visible: showSettings,
                gridSize: model.puzzle.size,
                appearance: settings.appearance,
                gridLocked: false,
                onApply: { grid, appearance in
                    showSettings = false
                    if grid != model.puzzle.size { model.setGridSize(grid) }
                    if appearance != settings.appearance { settings.setAppearance(appearance) }
                },
                onDismiss: { showSettings = false }
            )
        }
        .task(id: TimerKey(phase: model.phase, paused: model.pausedHidden, base: model.elapsedMs)) {
            elapsed = model.elapsedMs
            while model.phase == .playing && !model.pausedHidden && !Task.isCancelled {
                elapsed = model.elapsedNow()
                await sleep(ms: timerRefreshMs)
            }
            elapsed = model.elapsedNow()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background { model.onBackground() }
            if phase == .active { model.onForeground() }
        }
        .onChange(of: model.phase) { phase in if phase == .won { Haptics.success() } }
        .onChange(of: model.puzzle.tiles) { _ in if model.phase == .shuffling { Haptics.tick() } }
        .onChange(of: model.countdown) { count in if count > 0 { Haptics.tap() } }
        .task(id: model.message) {
            guard model.message != nil else { return }
            await sleep(ms: messageMs)
            if !Task.isCancelled { model.dismissMessage() }
        }
    }

    private struct TimerKey: Equatable {
        let phase: GamePhase
        let paused: Bool
        let base: Int64
    }

    @ViewBuilder
    private var controls: some View {
        InfoRow(model: model)
        switch model.phase {
        case .ready:
            PictureRow(
                customSelected: model.customImage != nil,
                cameraAvailable: model.picker.cameraAvailable,
                onScenic: model.useScenic,
                onCamera: model.picker.takePhoto,
                onGallery: model.picker.pickFromGallery
            )
            PrimaryButton(title: "Start", systemImage: "play.fill", enabled: !model.loadingPhoto, action: model.start)
        case .shuffling:
            hint("Shuffling…")
        case .countdown:
            hint("Get ready…")
        case .playing:
            hint("Tap any tile in the gap's row or column to slide it.")
        case .won:
            EmptyView()
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundColor(palette.secondaryText).padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func board(_ image: CGImage) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return GlassSurface(shape: shape) {
            ZStack {
                BoardView(
                    state: model.puzzle,
                    image: image,
                    interactive: model.phase == .playing,
                    slideMs: model.phase == .shuffling ? Int(shuffleStepMs) - 10 : slideMillis
                ) { id in
                    Haptics.tap()
                    model.tapTile(id)
                }
                if model.pausedHidden {
                    GlassSurface(cornerRadius: 16, solid: true) {
                        Text("Paused").font(.system(size: 22, weight: .bold)).foregroundColor(palette.text)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                if model.phase == .countdown { CountdownBadge(count: model.countdown) }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(12)
        }
        .overlay(shape.strokeBorder(palette.accent, lineWidth: 3))
        .shadow(color: palette.accent.opacity(0.6), radius: 16)
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct InfoRow: View {
    @ObservedObject var model: GameModel
    @Environment(\.palette) private var palette

    var body: some View {
        let size = model.puzzle.size
        HStack {
            Text("\(size)×\(size) · \(model.mode == .timeBased ? "Time attack" : "Free play")")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(palette.text)
            Spacer()
            Text("Moves \(model.puzzle.moves)").tabularNumbers(15, weight: .regular).foregroundColor(palette.secondaryText)
        }
        .padding(.horizontal, 6)
    }
}

/// The 3-2-1 shown over the scrambled board; each number pops in and fades out.
private struct CountdownBadge: View {
    let count: Int

    var body: some View {
        ZStack {
            GlassSurface(shape: Circle(), solid: true) {
                Text("\(count)")
                    .displayStyle(72)
                    .gradientForeground(CandyCta.titleGradient)
                    .frame(width: 132, height: 132)
            }
            .id(count)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.6).combined(with: .opacity),
                removal: .scale(scale: 0.6).combined(with: .opacity)
            ))
        }
        .animation(.easeInOut(duration: 0.3), value: count)
    }
}
