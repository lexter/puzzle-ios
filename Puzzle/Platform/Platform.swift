import AVFoundation
import PhotosUI
import UIKit

enum PickResult {
    case picked(Data)
    case cancelled
    case permissionDenied
}

/// "ios"; sent in the P2P handshake.
let platformName = "ios"

enum DeviceName {
    @MainActor static func get() -> String { UIDevice.current.name }
}

/// Opens this app's page in the system Settings (for denied permissions).
@MainActor
func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

/// Gallery (PHPicker) and camera (UIImagePickerController), presented over the current screen.
@MainActor
final class ImagePicker {
    private let deliver: (PickResult) -> Void
    // UIKit holds delegates weakly; keep them alive here.
    private var galleryDelegate: GalleryDelegate?
    private var cameraDelegate: CameraDelegate?

    init(deliver: @escaping (PickResult) -> Void) { self.deliver = deliver }

    var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func pickFromGallery() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        let delegate = GalleryDelegate(deliver: deliver)
        galleryDelegate = delegate
        picker.delegate = delegate
        topViewController()?.present(picker, animated: true)
    }

    func takePhoto() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted { self.presentCamera() } else { self.deliver(.permissionDenied) }
                }
            }
        default:
            deliver(.permissionDenied)
        }
    }

    private func presentCamera() {
        guard cameraAvailable else { return deliver(.cancelled) }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let delegate = CameraDelegate(deliver: deliver)
        cameraDelegate = delegate
        picker.delegate = delegate
        topViewController()?.present(picker, animated: true)
    }
}

private final class GalleryDelegate: NSObject, PHPickerViewControllerDelegate {
    private let deliver: (PickResult) -> Void

    init(deliver: @escaping (PickResult) -> Void) { self.deliver = deliver }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return deliver(.cancelled) }
        let deliver = self.deliver
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, _ in
            DispatchQueue.main.async { deliver(data.map(PickResult.picked) ?? .cancelled) }
        }
    }
}

private final class CameraDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let deliver: (PickResult) -> Void

    init(deliver: @escaping (PickResult) -> Void) { self.deliver = deliver }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
        deliver(data.map(PickResult.picked) ?? .cancelled)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        deliver(.cancelled)
    }
}

@MainActor
private func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}

/// Haptic feedback for tile moves, the start-of-game shuffle and wins.
@MainActor
enum Haptics {
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    /// Light impact for tapping or sliding a tile.
    static func tap() { impact.impactOccurred() }

    /// Softer tick for rapid, automatic tile moves such as the start-of-game shuffle.
    static func tick() { selection.selectionChanged() }

    static func success() { notification.notificationOccurred(.success) }
}
