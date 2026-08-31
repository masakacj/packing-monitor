import Dispatch
import Foundation

let environment = ProcessInfo.processInfo.environment
let host = environment["PACKING_MONITOR_HOST"] ?? "127.0.0.1"
let port = Int(environment["PACKING_MONITOR_PORT"] ?? "8787") ?? 8787
let startedAt = Date()
let serviceVersion = "0.3.0"
let captureService = CameraCaptureService()

func dashboardURL(host: String, port: Int) -> String {
    let browserHost: String
    switch host {
    case "0.0.0.0", "::":
        browserHost = "127.0.0.1"
    default:
        browserHost = host
    }
    return "http://\(browserHost):\(port)"
}

func openDashboard(_ url: String) {
    let opener = Process()
    opener.launchPath = "/usr/bin/open"
    opener.arguments = [url]
    opener.launch()
}

do {
    let server = try HTTPServer(host: host, port: port) { request, respond in
        switch (request.method, request.path) {
        case ("GET", "/"):
            respond(.text(Dashboard.html, contentType: "text/html; charset=utf-8"))

        case ("GET", "/api/health"):
            respond(.json(HealthResponse(
                ok: true,
                service: "packing-monitor",
                time: Date()
            )))

        case ("GET", "/api/status"):
            let cameras = CameraCatalog.videoDevices()
            respond(.json(ServiceStatusResponse(
                service: "packing-monitor",
                version: serviceVersion,
                startedAt: startedAt,
                uptimeSeconds: Date().timeIntervalSince(startedAt),
                cameraPermission: CameraCatalog.permissionStatus(),
                cameraCount: cameras.count
            )))

        case ("GET", "/api/cameras"):
            respond(.json(CameraListResponse(
                permission: CameraCatalog.permissionStatus(),
                cameras: CameraCatalog.videoDevices()
            )))

        case ("POST", "/api/camera/authorize"):
            guard CameraCatalog.hasCameraUsageDescription else {
                respond(.json(CameraAuthorizationResponse(
                    granted: false,
                    status: "host_missing_camera_usage_description"
                )))
                return
            }

            CameraCatalog.requestPermission { granted in
                respond(.json(CameraAuthorizationResponse(
                    granted: granted,
                    status: CameraCatalog.permissionStatus()
                )))
            }

        case ("GET", "/api/camera/capture-status"):
            respond(.json(captureService.status()))

        case ("POST", "/api/camera/start"):
            captureService.startPreferredCamera { result in
                switch result {
                case .success:
                    respond(.json(CameraCaptureActionResponse(
                        ok: true,
                        error: nil,
                        capture: captureService.status()
                    )))
                case .failure(let error):
                    respond(.json(CameraCaptureActionResponse(
                        ok: false,
                        error: error.localizedDescription,
                        capture: captureService.status()
                    )))
                }
            }

        case ("POST", "/api/camera/stop"):
            captureService.stop {
                respond(.json(CameraCaptureActionResponse(
                    ok: true,
                    error: nil,
                    capture: captureService.status()
                )))
            }

        case ("GET", "/api/camera/frame.jpg"):
            guard let jpeg = captureService.previewJPEG() else {
                respond(.empty(statusCode: 204))
                return
            }
            respond(.data(jpeg, contentType: "image/jpeg"))

        default:
            respond(.text("Not Found", statusCode: 404))
        }
    }

    server.start()
    let url = dashboardURL(host: host, port: port)
    print("Packing Monitor \(serviceVersion) listening on \(url)")

    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
        openDashboard(url)
    }

    dispatchMain()
} catch {
    fputs("Packing Monitor failed to start: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
