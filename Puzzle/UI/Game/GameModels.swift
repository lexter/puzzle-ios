import Foundation

/// Messages shown in a toast on the game, lobby and photo screens.
enum UserMessage: Equatable {
    case photoTooSmall
    case photoUnreadable
    case cameraDenied

    var text: String {
        switch self {
        case .photoTooSmall: return "That photo is too small. Pick a bigger one."
        case .photoUnreadable: return "That photo couldn't be opened."
        case .cameraDenied: return "Camera access is off. You can turn it on in Settings."
        }
    }

    static func from(_ error: PuzzleImageError) -> UserMessage { error == .tooSmall ? .photoTooSmall : .photoUnreadable }
}

/// Runs image preparation off the main actor.
func preparePhoto(_ bytes: Data) async -> Result<ChosenPhoto, PuzzleImageError> {
    await Task.detached(priority: .userInitiated) {
        PuzzleImage.prepare(bytes).map { ChosenPhoto(image: $0, jpeg: ImageCodec.encodeJpeg($0, quality: PuzzleImage.p2pJpegQuality)) }
    }.value
}
