import Foundation

struct HealthResponse: Codable {
    let ok: Bool
    let service: String
    let time: Date
}

struct ServiceStatusResponse: Codable {
    let service: String
    let version: String
    let startedAt: Date
    let uptimeSeconds: Double
    let cameraPermission: String
    let cameraCount: Int
    let preferredCameraID: String?
}

struct CameraListResponse: Codable {
    let permission: String
    let cameras: [CameraInfo]
}

struct CameraAuthorizationResponse: Codable {
    let granted: Bool
    let status: String
}

struct CameraCaptureStatusResponse: Codable {
    let running: Bool
    let deviceID: String?
    let deviceName: String?
    let capturedWidth: Int32
    let capturedHeight: Int32
    let lastFrameAt: Date?
    let previewAvailable: Bool
}

struct CameraCaptureActionResponse: Codable {
    let ok: Bool
    let error: String?
    let capture: CameraCaptureStatusResponse
}

struct CameraInfo: Codable {
    let id: String
    let name: String
    let manufacturer: String
    let modelID: String
    let deviceType: String
    let position: String
    let connected: Bool
    let suspended: Bool
    let formatCount: Int
    let maxWidth: Int32
    let maxHeight: Int32
    let maxFPS: Double
}
