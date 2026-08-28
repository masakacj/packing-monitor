import Foundation
import Hummingbird

@main
struct PackingMonitorApp {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let host = environment["PACKING_MONITOR_HOST"] ?? "127.0.0.1"
        let port = Int(environment["PACKING_MONITOR_PORT"] ?? "8787") ?? 8787
        let startedAt = Date()
        let serviceVersion = "0.2.0"
        let captureService = CameraCaptureService()

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

        router.get("/api/camera/capture-status") { _, _ -> CameraCaptureStatusResponse in
            captureService.status()
        }

        router.post("/api/camera/start") { _, _ -> CameraCaptureActionResponse in
            do {
                try await captureService.startPreferredCamera()
                return CameraCaptureActionResponse(
                    ok: true,
                    error: nil,
                    capture: captureService.status()
                )
            } catch {
                return CameraCaptureActionResponse(
                    ok: false,
                    error: error.localizedDescription,
                    capture: captureService.status()
                )
            }
        }

        router.post("/api/camera/stop") { _, _ -> CameraCaptureActionResponse in
            await captureService.stop()
            return CameraCaptureActionResponse(
                ok: true,
                error: nil,
                capture: captureService.status()
            )
        }

        router.get("/api/camera/frame.jpg") { _, _ -> Response in
            guard let jpeg = captureService.previewJPEG() else {
                return Response(status: .noContent)
            }
            return Response(
                status: .ok,
                headers: [.contentType: "image/jpeg"],
                body: .init(byteBuffer: ByteBuffer(bytes: jpeg))
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(host, port: port))
        )

        try await app.runService()
    }
}
