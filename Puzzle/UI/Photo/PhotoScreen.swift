import SwiftUI

/// "Make your puzzle": pick a camera/gallery photo (or the scenic default) and a grid size.
@MainActor
final class PhotoModel: ObservableObject, ScreenModel {
    private let settings: SettingsStore
    private let selection: PhotoSelection
    @Published private(set) var photo: ChosenPhoto?
    @Published private(set) var grid: Int
    @Published private(set) var loading = false
    @Published private(set) var message: UserMessage?
    private(set) lazy var picker = ImagePicker { [weak self] in self?.setPicture($0) }

    init(settings: SettingsStore, selection: PhotoSelection) {
        self.settings = settings
        self.selection = selection
        photo = selection.chosen
        grid = settings.gridSize
    }

    func setPicture(_ result: PickResult) {
        switch result {
        case .cancelled: break
        case .permissionDenied: message = .cameraDenied
        case .picked(let bytes):
            loading = true
            Task {
                switch await preparePhoto(bytes) {
                case .success(let photo):
                    selection.choose(photo)
                    self.photo = photo
                    loading = false
                case .failure(let error):
                    loading = false
                    message = .from(error)
                }
            }
        }
    }

    func useScenic() {
        selection.choose(nil)
        photo = nil
    }

    func setGrid(_ size: Int) {
        let clamped = size.clamped(to: PuzzleState.minSize...PuzzleState.maxSize)
        grid = clamped
        settings.setGridSize(clamped)
    }

    func dismissMessage() { message = nil }
}

/// "Make your puzzle": the photo is the hero, with the tile grid drawn over it.
struct PhotoScreen: View {
    @ObservedObject var model: PhotoModel
    let onBack: () -> Void
    let onRace: () -> Void
    let onSolo: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let image = model.photo?.image ?? Scenic.image
        let grid = model.grid
        ScreenScaffold {
            ZStack {
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            GlassIconButton(systemImage: "arrow.left", label: "Back", action: onBack)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Make your puzzle").displayStyle(22).foregroundColor(palette.text)
                                Text("Any photo becomes a \(grid)×\(grid) board").font(.system(size: 13)).foregroundColor(palette.secondaryText)
                            }
                            Spacer()
                        }

                        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                        ZStack {
                            Image(decorative: image, scale: 1).resizable().scaledToFill()
                            GridOverlay(n: grid, accent: palette.accent)
                            if model.loading { ProgressView().tint(.white) }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(palette.accent, lineWidth: 3))
                        .shadow(color: palette.accent.opacity(0.6), radius: 14)
                        .padding(6)
                        .accessibilityElement()
                        .accessibilityLabel("Puzzle picture preview, cut into \(grid) by \(grid) tiles")

                        HStack(spacing: 6) {
                            ForEach(PuzzleState.sizes, id: \.self) { n in
                                GridChip(n: n, selected: n == grid) { model.setGrid(n) }
                            }
                        }

                        HStack {
                            SourceTile(systemImage: "photo.on.rectangle", label: "Gallery") { model.picker.pickFromGallery() }
                            Spacer()
                            Shutter(enabled: model.picker.cameraAvailable) { model.picker.takePhoto() }
                            Spacer()
                            SourceTile(systemImage: "photo", label: "Scenic", action: model.useScenic)
                        }
                        .padding(.horizontal, 8)

                        Spacer().frame(height: 4)
                        PrimaryButton(title: "Race with this photo", systemImage: "bolt.fill", enabled: !model.loading, action: onRace)
                        GlassButton(title: "Play solo", systemImage: "person.fill", action: onSolo)
                    }
                    .frame(maxWidth: 520)
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
        .task(id: model.message) {
            guard model.message != nil else { return }
            await sleep(ms: 4_000)
            if !Task.isCancelled { model.dismissMessage() }
        }
    }
}

/// White cut lines plus corner brackets in the player's color.
private struct GridOverlay: View {
    let n: Int
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let cell = size.width / CGFloat(n)
            var lines = Path()
            for i in 1..<n {
                lines.move(to: CGPoint(x: CGFloat(i) * cell, y: 0))
                lines.addLine(to: CGPoint(x: CGFloat(i) * cell, y: size.height))
                lines.move(to: CGPoint(x: 0, y: CGFloat(i) * cell))
                lines.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * cell))
            }
            context.stroke(lines, with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            let inset: CGFloat = 12
            let arm: CGFloat = 24
            var brackets = Path()
            let corners: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: inset, y: inset), 1, 1),
                (CGPoint(x: size.width - inset, y: inset), -1, 1),
                (CGPoint(x: inset, y: size.height - inset), 1, -1),
                (CGPoint(x: size.width - inset, y: size.height - inset), -1, -1),
            ]
            for (corner, dx, dy) in corners {
                brackets.move(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
                brackets.move(to: corner)
                brackets.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
            }
            context.stroke(brackets, with: .color(accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

private struct GridChip: View {
    let n: Int
    let selected: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            Text("\(n)×\(n)")
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(selected ? palette.onAccent : palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(shape.fill(selected ? palette.accent : palette.glassTint))
                .overlay(shape.strokeBorder(selected ? palette.accent : palette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SourceTile: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            GlassSurface(cornerRadius: 20) {
                VStack(spacing: 4) {
                    Image(systemName: systemImage).font(.system(size: 20, weight: .semibold)).foregroundColor(palette.accent)
                    Text(label).font(.system(size: 13, weight: .semibold)).foregroundColor(palette.text)
                }
                .frame(width: 92, height: 66)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Big round camera button.
private struct Shutter: View {
    let enabled: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
                .background(Circle().fill(LinearGradient(colors: [Color(argb: 0xFF4FD1FF), Color(argb: 0xFFFF4FA3)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                .shadow(color: palette.accent.opacity(0.6), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel("Take a photo")
    }
}
