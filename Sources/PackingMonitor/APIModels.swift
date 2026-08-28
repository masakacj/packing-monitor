import Foundation
import Hummingbird

struct HealthResponse: ResponseEncodable {
    let ok: Bool
    let service: String
    let time: Date
}

struct ServiceStatusResponse: ResponseEncodable {
    let service: String
    let version: String
    let startedAt: Date
    let uptimeSeconds: Double
    let cameraPermission: String
    let cameraCount: Int
}

struct CameraListResponse: ResponseEncodable {
    let permission: String
    let cameras: [CameraInfo]
}

struct CameraAuthorizationResponse: ResponseEncodable {
    let granted: Bool
    let status: String
}

struct CameraInfo: Codable, Sendable {
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

extension CameraInfo: ResponseEncodable {}
