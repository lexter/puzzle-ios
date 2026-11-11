import SwiftUI

let sameNetworkNote = "Both devices must be on the same Wi-Fi or one phone's hotspot. No internet needed."
let noHostsText = "No games found yet. Same Wi-Fi or hotspot? Local network access allowed?"

struct LobbyScreen: View {
    @ObservedObject var model: LobbyModel
    let onBack: () -> Void
    let onRaceStarting: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let match = model.match
        ScreenScaffold {
            ZStack {
                // The radar sweep is the screen's background; cards sit on top of it.
                Radar(peers: model.tab == .join ? model.hosts.map(\.name) : [match?.peerName].compactMap { $0 })
                    .frame(width: radarSize, height: radarSize)
                    .offset(y: 60)
                    .opacity(0.85)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            GlassIconButton(systemImage: "arrow.left", label: "Back", action: onBack)
                            Text("Find a rival").displayStyle(24).foregroundColor(palette.text)
                        }
                        SegmentedControl(
                            segments: [Segment(value: LobbyTab.host, label: "Host a race"), Segment(value: LobbyTab.join, label: "Join a race")],
                            selected: model.tab,
                            height: 44,
                            enabled: match == nil || match?.phase == .lost,
                            onSelect: model.selectTab
                        )

                        if model.tab == .host {
                            HostCard(model: model, match: match)
                        } else {
                            JoinList(model: model, waitingForHost: match != nil)
                        }

                        if let error = model.error {
                            Text(error).font(.system(size: 14)).foregroundColor(palette.text)
                            GlassButton(title: "Try again", action: model.retry)
                        }
                        Text(sameNetworkNote)
                            .font(.system(size: 13)).foregroundColor(palette.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }

                MessageToast(
                    text: model.message?.text,
                    actionLabel: model.message == .cameraDenied ? "Settings" : nil,
                    onAction: openAppSettings,
                    onDismiss: model.dismissMessage
                )
            }
        }
        .onChange(of: match?.phase) { phase in
            if phase == .countdown || phase == .racing {
                model.handOff()
                onRaceStarting()
            }
            if phase == .lost { model.onMatchLost() }
        }
        .task(id: model.message) {
            guard model.message != nil else { return }
            await sleep(ms: 4_000)
            if !Task.isCancelled { model.dismissMessage() }
        }
    }
}

private struct HostCard: View {
    @ObservedObject var model: LobbyModel
    let match: MatchSnapshot?
    @Environment(\.palette) private var palette

    var body: some View {
        let configured = match?.phase == .configured
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(text: "Match you're hosting")
                HStack(spacing: 14) {
                    Image(decorative: model.customImage ?? Scenic.image, scale: 1)
                        .resizable().scaledToFill()
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Puzzle picture")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.grid)×\(model.grid) · \(model.mode == .timeBased ? "Time-based" : "Free play")")
                            .font(.system(size: 18, weight: .semibold)).foregroundColor(palette.text)
                        Text("Same shuffle for both players").font(.system(size: 14)).foregroundColor(palette.secondaryText)
                    }
                }
                if !configured {
                    SegmentedControl(
                        segments: PuzzleState.sizes.map { Segment(value: $0, label: "\($0)") },
                        selected: model.grid,
                        height: 38,
                        onSelect: model.setGrid
                    )
                    HStack(spacing: 10) {
                        PictureChip(systemImage: "photo", label: "Scenic", selected: model.customImage == nil, enabled: true, action: model.useScenic)
                        PictureChip(systemImage: "camera.fill", label: "Camera", selected: false, enabled: model.picker.cameraAvailable, action: model.picker.takePhoto)
                        PictureChip(systemImage: "photo.on.rectangle", label: "Gallery", selected: model.customImage != nil, enabled: true, action: model.picker.pickFromGallery)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "wifi").font(.system(size: 16, weight: .semibold)).foregroundColor(palette.accent)
                    Text("Visible as “\(model.myName)” on this network").font(.system(size: 14)).foregroundColor(palette.text)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.accent.opacity(0.12)))
            }
            .padding(18)
        }

        if let peerName = match?.peerName {
            if !configured {
                PlayerRow(name: peerName, status: "wants to join", actionLabel: "Accept", onAction: model.accept, secondary: ("Decline", model.decline))
            } else {
                let ready = match?.peerReady == true
                PlayerRow(name: peerName, status: ready ? "ready" : "getting ready…", actionLabel: nil, onAction: {})
                PrimaryButton(title: "Start race · 3-2-1", enabled: ready, action: model.startRace)
            }
        } else {
            Waiting(text: "Waiting for a player to join…")
        }
    }
}

private struct JoinList: View {
    @ObservedObject var model: LobbyModel
    let waitingForHost: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        if waitingForHost {
            Waiting(text: "Connected. Waiting for the host to start…")
        } else {
            SectionLabel(text: "Games nearby")
            if model.hosts.isEmpty {
                Waiting(text: "Looking for games…")
                if model.noHostsHint {
                    Text(noHostsText).font(.system(size: 14)).foregroundColor(palette.text)
                    GlassButton(title: "Retry", action: model.retry)
                }
            }
            ForEach(model.hosts) { host in
                let busy = model.joining == host.name
                PlayerRow(name: host.name, status: busy ? "connecting…" : "hosting a game", actionLabel: busy ? nil : "Join") { model.join(host) }
            }
        }
    }
}

private struct Waiting: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().frame(width: 20, height: 20)
            Text(text).font(.system(size: 15)).foregroundColor(palette.secondaryText)
        }
    }
}

private struct PlayerRow: View {
    let name: String
    let status: String
    let actionLabel: String?
    let onAction: () -> Void
    var secondary: (String, () -> Void)?
    @Environment(\.palette) private var palette

    var body: some View {
        GlassSurface(cornerRadius: 20) {
            HStack(spacing: 12) {
                Avatar(name: name, color: palette.opponentAccent, size: 42)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.system(size: 16, weight: .semibold)).foregroundColor(palette.text).lineLimit(1)
                    Text(status).font(.system(size: 13)).foregroundColor(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let (label, action) = secondary {
                    Button(action: action) {
                        Text(label).font(.system(size: 16, weight: .semibold)).foregroundColor(palette.secondaryText)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                }
                if let actionLabel {
                    Button(action: onAction) {
                        Text(actionLabel).font(.system(size: 16, weight: .heavy)).foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CandyCta.gradient))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private let radarSize: CGFloat = 640
private let radarScale = radarSize / 220
private let blipSlots: [(CGFloat, CGFloat)] = [(62, -58), (-70, 52), (74, 60), (-60, -66)]

/// Radar sweep with the local player in the middle and found players as blips around it.
private struct Radar: View {
    let peers: [String]
    @Environment(\.palette) private var palette
    @State private var sweeping = false

    var body: some View {
        let ring = palette.accent
        ZStack {
            ForEach(1...3, id: \.self) { k in
                Circle()
                    .stroke(ring.opacity(0.18 + 0.08 * Double(k)), lineWidth: 1)
                    .frame(width: radarSize * CGFloat(k) / 3, height: radarSize * CGFloat(k) / 3)
            }
            Circle()
                .fill(AngularGradient(gradient: Gradient(colors: [ring.opacity(0.45), .clear, .clear, .clear]), center: .center))
                .rotationEffect(.degrees(sweeping ? 360 : 0))
                .animation(.linear(duration: 2.6).repeatForever(autoreverses: false), value: sweeping)
            Avatar(name: "You", color: palette.accent, size: 50, glow: true)
            ForEach(Array(peers.prefix(blipSlots.count).enumerated()), id: \.offset) { index, name in
                let (dx, dy) = blipSlots[index]
                Avatar(name: name, color: index == 0 ? palette.opponentAccent : palette.gold, size: 36, glow: true)
                    .offset(x: dx * radarScale, y: dy * radarScale)
            }
        }
        .onAppear { sweeping = true }
        .accessibilityElement()
        .accessibilityLabel(peers.isEmpty ? "Searching nearby" : "\(peers.count) nearby")
    }
}
