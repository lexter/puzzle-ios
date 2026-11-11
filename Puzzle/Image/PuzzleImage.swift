import ImageIO
import UIKit

enum PuzzleImageError: Error, Equatable {
    case tooSmall
    case decodeFailed

    var message: String {
        switch self {
        case .tooSmall: return "This photo is too small to make a puzzle."
        case .decodeFailed: return "This photo couldn't be opened."
        }
    }
}

extension Result {
    var isSuccess: Bool { if case .success = self { return true } else { return false } }
}

/// Decoding (EXIF orientation applied, downsampled while decoding), cropping and JPEG encoding.
enum ImageCodec {
    /// Decodes `bytes`, downsampling so the longest side is at most `maxSide`. Nil if unreadable.
    static func decode(_ bytes: Data, maxSide: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func encodeJpeg(_ image: CGImage, quality: Int) -> Data {
        UIImage(cgImage: image).jpegData(compressionQuality: CGFloat(quality) / 100) ?? Data()
    }
}

enum PuzzleImage {
    static let maxSide = 1024
    static let minSide = 64
    static let p2pJpegQuality = 80

    /// Largest centered square inside a `width`×`height` picture.
    static func cropRect(width: Int, height: Int) -> CGRect {
        let side = min(width, height)
        return CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
    }

    /// Decode → center square crop → at most `maxSide` px.
    static func prepare(_ bytes: Data) -> Result<CGImage, PuzzleImageError> {
        guard let decoded = ImageCodec.decode(bytes, maxSide: 2 * maxSide) else { return .failure(.decodeFailed) }
        guard min(decoded.width, decoded.height) >= minSide else { return .failure(.tooSmall) }
        let rect = cropRect(width: decoded.width, height: decoded.height)
        guard let scaled = cropScaled(decoded, source: rect, side: min(Int(rect.width), maxSide)) else { return .failure(.decodeFailed) }
        return .success(scaled)
    }

    static func cropScaled(_ image: CGImage, source: CGRect, side: Int) -> CGImage? {
        guard let cropped = image.cropping(to: source) else { return nil }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let drawn = renderer.image { context in
            context.cgContext.interpolationQuality = .high
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return drawn.cgImage
    }
}

/// A prepared custom picture: the square bitmap for the board and its JPEG for sending to a peer.
struct ChosenPhoto {
    let image: CGImage
    let jpeg: Data
}

/// The photo picked on "Make your puzzle", shared with the solo game and the lobby so the
/// player's own picture follows them into whichever mode they start. Nil = scenic default.
@MainActor
final class PhotoSelection: ObservableObject {
    @Published private(set) var chosen: ChosenPhoto?

    func choose(_ photo: ChosenPhoto?) { chosen = photo }
}

/// The bundled default picture (square, 1024 px).
@MainActor
enum Scenic {
    static let image: CGImage = {
        guard let image = UIImage(named: "scenic_default")?.cgImage else { fatalError("scenic_default image missing") }
        return image
    }()
}
