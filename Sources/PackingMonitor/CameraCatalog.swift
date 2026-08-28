import AVFoundation
import CoreMedia
import Foundation

/// Read-only AVFoundation camera diagnostics used by the first milestone.
///
/// Capture/recording is deliberately not started here. First we need to verify
/// what the X-T2 / FUJIFILM X Webcam path actually exposes to AVFoundation.
enum CameraCatalog {
    static func permissionStatus() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }

    static func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func videoDevices() -> [CameraInfo] {
        // `devices(for:)` is deprecated in favor of DiscoverySession, but it is
        // intentionally used in this diagnostic milestone because it returns all
        // video devices, including virtual/external camera types that can vary by
        // macOS/FUJIFILM driver version. We will narrow the discovery types after
        // seeing the real X-T2 device classification.
        let devices = AVCaptureDevice.devices(for: .video)

        return devices
            .map(makeCameraInfo)
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static func makeCameraInfo(device: AVCaptureDevice) -> CameraInfo {
        var bestDimensions = CMVideoDimensions(width: 0, height: 0)
        var bestArea: Int64 = 0
        var maximumFPS = 0.0

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let area = Int64(dimensions.width) * Int64(dimensions.height)
            if area > bestArea {
                bestArea = area
                bestDimensions = dimensions
            }

            for range in format.videoSupportedFrameRateRanges {
                maximumFPS = max(maximumFPS, range.maxFrameRate)
            }
        }

        return CameraInfo(
            id: device.uniqueID,
            name: device.localizedName,
            manufacturer: device.manufacturer,
            modelID: device.modelID,
            deviceType: device.deviceType.rawValue,
            position: positionName(device.position),
            connected: device.isConnected,
            suspended: device.isSuspended,
            formatCount: device.formats.count,
            maxWidth: bestDimensions.width,
            maxHeight: bestDimensions.height,
            maxFPS: maximumFPS
        )
    }

    private static func positionName(_ position: AVCaptureDevice.Position) -> String {
        switch position {
        case .front:
            return "front"
        case .back:
            return "back"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }
}
