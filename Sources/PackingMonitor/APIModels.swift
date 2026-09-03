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

struct NormalizedRect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct RecognitionHit: Codable {
    let trackingNumber: String
    let rawValue: String
    let source: String
    let symbology: String?
    let confidence: Double
    let detectedAt: Date
    let boundingBox: NormalizedRect
}

struct RecognitionStatusResponse: Codable {
    let enabled: Bool
    let totalConfirmed: Int
    let lastHit: RecognitionHit?
    let lastError: String?
}

struct StorageStatusResponse: Codable {
    let rootPath: String?
    let configured: Bool
    let available: Bool
    let writable: Bool
    let recordingEnabled: Bool
    let segmentMinutes: Int
    let mountedVolumes: [String]
    let error: String?
}

struct StorageConfigActionResponse: Codable {
    let ok: Bool
    let error: String?
    let storage: StorageStatusResponse
}

struct StorageFolderSelectionResponse: Codable {
    let ok: Bool
    let path: String?
    let error: String?
}

struct RecordingStatusResponse: Codable {
    let recording: Bool
    let currentPath: String?
    let segmentStartedAt: Date?
    let segmentDurationSeconds: Double
    let lastError: String?
}

struct DetectionEvent: Codable {
    let id: String
    let trackingNumber: String
    let rawValue: String
    let source: String
    let symbology: String?
    let confidence: Double
    let detectedAt: Date
    let boundingBox: NormalizedRect
    let deviceName: String?
    let videoPath: String?
    let segmentStartedAt: Date?
    let offsetSeconds: Double?
}

struct DetectionSearchResponse: Codable {
    let query: String
    let results: [DetectionEvent]
}

struct EventActionResponse: Codable {
    let ok: Bool
    let error: String?
}
