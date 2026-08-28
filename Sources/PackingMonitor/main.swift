import Foundation
import Hummingbird

@main
struct PackingMonitorApp {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let host = environment["PACKING_MONITOR_HOST"] ?? "127.0.0.1"
        let port = Int(environment["PACKING_MONITOR_PORT"] ?? "8787") ?? 8787
        let startedAt = Date()
        let serviceVersion = "0.1.0"

        let router = Router()

        router.get("/") { _, _ -> EditedResponse in
            .init(
                status: .ok,
                headers: [.contentType: "text/html; charset=utf-8"],
                response: Dashboard.html
            )
        }

        router.get("/api/health") { _, _ -> HealthResponse in
            HealthResponse(
                ok: true,
                service: "packing-monitor",
                time: Date()
            )
        }

        router.get("/api/status") { _, _ -> ServiceStatusResponse in
            let cameras = CameraCatalog.videoDevices()
            return ServiceStatusResponse(
                service: "packing-monitor",
                version: serviceVersion,
                startedAt: startedAt,
                uptimeSeconds: Date().timeIntervalSince(startedAt),
                cameraPermission: CameraCatalog.permissionStatus(),
                cameraCount: cameras.count
            )
        }

        router.get("/api/cameras") { _, _ -> CameraListResponse in
            CameraListResponse(
                permission: CameraCatalog.permissionStatus(),
                cameras: CameraCatalog.videoDevices()
            )
        }

        router.post("/api/camera/authorize") { _, _ -> CameraAuthorizationResponse in
            guard CameraCatalog.hasCameraUsageDescription else {
                return CameraAuthorizationResponse(
                    granted: false,
                    status: "host_missing_camera_usage_description"
                )
            }

            let granted = await CameraCatalog.requestPermission()
            return CameraAuthorizationResponse(
                granted: granted,
                status: CameraCatalog.permissionStatus()
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port))
        )

        try await app.runService()
    }
}
