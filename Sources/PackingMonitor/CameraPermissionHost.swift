import Foundation

extension CameraCatalog {
    /// Requesting camera access without this key raises an exception on macOS.
    /// SwiftPM development binaries do not automatically carry an Info.plist,
    /// so the API refuses to request access until we run from the packaged host.
    static var hasCameraUsageDescription: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
