import SwiftUI

let slideMillis = 160

/// Square board. Each tile shows its home slice of `image` (which must be square) and
/// animates to its current cell. Taps report the tile number, not its index.
struct BoardView: View {
    let state: PuzzleState
    let image: CGImage
    var interactive = true
    var slideMs = slideMillis
    var onTileTap: (Int) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let n = state.size
            let board = min(geo.size.width, geo.size.height)
            let gap: CGFloat = board < 200 ? 2 : 4
            let tile = (board - gap * CGFloat(n - 1)) / CGFloat(n)
            let slices = TileSlices.shared.slices(of: image, n: n)
            let positions = Dictionary(uniqueKeysWithValues: state.tiles.enumerated().map { ($0.element, $0.offset) })
            ZStack(alignment: .topLeading) {
                ForEach(1..<(n * n), id: \.self) { id in
                    let index = positions[id] ?? id
                    TileView(slice: slices[id], side: tile, id: id)
                        .offset(x: CGFloat(index % n) * (tile + gap), y: CGFloat(index / n) * (tile + gap))
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Double(slideMs) / 1000), value: index)
                        .onTapGesture { if interactive { onTileTap(id) } }
                        .allowsHitTesting(interactive)
                }
            }
            .frame(width: board, height: board, alignment: .topLeading)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct TileView: View {
    let slice: CGImage?
    let side: CGFloat
    let id: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        Group {
            if let slice {
                Image(decorative: slice, scale: 1).resizable().interpolation(.medium)
            } else {
                Color.gray
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5))
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel("Tile \(id)")
        .accessibilityAddTraits(.isButton)
    }
}

/// Caches each picture's tile slices so redraws don't re-crop the image. Entries hold their
/// image, so identity comparison can't match a different, later picture.
@MainActor
private final class TileSlices {
    static let shared = TileSlices()
    private var entries: [(image: CGImage, n: Int, slices: [CGImage?])] = []

    func slices(of image: CGImage, n: Int) -> [CGImage?] {
        if let hit = entries.first(where: { $0.image === image && $0.n == n }) { return hit.slices }
        let cell = CGFloat(image.width) / CGFloat(n)
        let result: [CGImage?] = (0..<(n * n)).map { home in
            let left = Int(CGFloat(home % n) * cell)
            let top = Int(CGFloat(home / n) * cell)
            let right = min(Int(CGFloat(home % n + 1) * cell), image.width)
            let bottom = min(Int(CGFloat(home / n + 1) * cell), image.height)
            return image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
        }
        if entries.count >= 8 { entries.removeFirst() }
        entries.append((image, n, result))
        return result
    }
}
