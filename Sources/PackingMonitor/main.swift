import Dispatch
import Foundation

let environment = ProcessInfo.processInfo.environment
let host = environment["PACKING_MONITOR_HOST"] ?? "127.0.0.1"
let port = Int(environment["PACKING_MONITOR_PORT"] ?? "8787") ?? 8787
let startedAt = Date()
let serviceVersion = "0.4.2"
let preferences = UserDefaults.standard
let preferredCameraKey = "preferredCameraID"
let storageManager = StorageManager(defaults: preferences)
let eventStore = DetectionEventStore(storage: storageManager)
let captureService = CameraCaptureService(storage: storageManager, eventStore: eventStore)

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

func enhancedMonitorDashboard() -> String {
    let navigation = """
    <a href="/manage" style="display:inline-block;margin-left:8px;padding:9px 12px;border:1px solid #343845;background:#20232b;color:#fff;border-radius:8px;text-decoration:none;font-size:13px">存储 / 运单查询</a>
    """
    return Dashboard.html.replacingOccurrences(of: "</header>", with: "\(navigation)</header>")
}

func revealInFinder(_ path: String) -> Result<Void, Error> {
    guard FileManager.default.fileExists(atPath: path) else {
        return .failure(AppActionError.fileNotFound)
    }
    let opener = Process()
    opener.launchPath = "/usr/bin/open"
    opener.arguments = ["-R", path]
    opener.launch()
    return .success(())
}

func openFile(_ path: String) -> Result<Void, Error> {
    guard FileManager.default.fileExists(atPath: path) else {
        return .failure(AppActionError.fileNotFound)
    }
    let opener = Process()
    opener.launchPath = "/usr/bin/open"
    opener.arguments = [path]
    opener.launch()
    return .success(())
}

func chooseStorageFolder() -> Result<String, Error> {
    let script = """
    set pickedFolder to choose folder with prompt "选择 Packing Monitor 保存位置（请选择 NAS / 外接存储）"
    POSIX path of pickedFolder
    """

    let picker = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    picker.launchPath = "/usr/bin/osascript"
    picker.arguments = ["-e", script]
    picker.standardOutput = outputPipe
    picker.standardError = errorPipe

    picker.launch()
    picker.waitUntilExit()

    if picker.terminationStatus != 0 {
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if detail.lowercased().contains("cancel") || detail.contains("-128") {
            return .failure(AppActionError.folderSelectionCancelled)
        }
        return .failure(AppActionError.folderPickerFailed(detail))
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard var path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
        return .failure(AppActionError.folderPickerFailed("未返回目录"))
    }
    while path.count > 1 && path.hasSuffix("/") {
        path.removeLast()
    }

    guard path.hasPrefix("/Volumes/") else {
        return .failure(AppActionError.storageFolderMustBeMountedVolume)
    }
    return .success(path)
}

func boolQuery(_ value: String?, default fallback: Bool) -> Bool {
    guard let value = value?.lowercased() else { return fallback }
    switch value {
    case "1", "true", "yes", "on": return true
    case "0", "false", "no", "off": return false
    default: return fallback
    }
}

func startCamera(for request: HTTPRequest, completion: @escaping (Result<Void, Error>) -> Void) {
    let devices = CameraCatalog.videoDevices()
    let availableIDs = Set(devices.map { $0.id })

    let requestedID = request.query["deviceID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let savedID = preferences.string(forKey: preferredCameraKey)

    let selectedID: String?
    if let requestedID = requestedID, !requestedID.isEmpty, availableIDs.contains(requestedID) {
        selectedID = requestedID
    } else if let savedID = savedID, availableIDs.contains(savedID) {
        selectedID = savedID
    } else {
        selectedID = nil
    }

    let finish: (Result<Void, Error>) -> Void = { result in
        if case .success = result, let activeID = captureService.status().deviceID {
            preferences.set(activeID, forKey: preferredCameraKey)
        }
        completion(result)
    }

    if let selectedID = selectedID {
        captureService.start(deviceID: selectedID, completion: finish)
    } else {
        captureService.startPreferredCamera(completion: finish)
    }
}

do {
    let server = try HTTPServer(host: host, port: port) { request, respond in
        switch (request.method, request.path) {
        case ("GET", "/"):
            respond(.text(enhancedMonitorDashboard(), contentType: "text/html; charset=utf-8"))

        case ("GET", "/manage"):
            respond(.text(ManagementDashboard.html, contentType: "text/html; charset=utf-8"))

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
                cameraCount: cameras.count,
                preferredCameraID: preferences.string(forKey: preferredCameraKey)
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
            startCamera(for: request) { result in
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

        case ("GET", "/api/recognition/status"):
            respond(.json(captureService.recognitionStatus()))

        case ("GET", "/api/storage/status"):
            respond(.json(storageManager.status()))

        case ("POST", "/api/storage/choose"):
            switch chooseStorageFolder() {
            case .success(let path):
                respond(.json(StorageFolderSelectionResponse(ok: true, path: path, error: nil)))
            case .failure(let error):
                respond(.json(StorageFolderSelectionResponse(ok: false, path: nil, error: error.localizedDescription)))
            }

        case ("POST", "/api/storage/config"):
            let current = storageManager.status()
            let rootPath = request.query["rootPath"] ?? current.rootPath ?? ""
            let recordingEnabled = boolQuery(request.query["recordingEnabled"], default: current.recordingEnabled)
            let segmentMinutes = Int(request.query["segmentMinutes"] ?? "") ?? current.segmentMinutes

            switch storageManager.configure(
                rootPath: rootPath,
                recordingEnabled: recordingEnabled,
                segmentMinutes: segmentMinutes
            ) {
            case .success(let storage):
                captureService.refreshRecordingConfiguration()
                respond(.json(StorageConfigActionResponse(ok: true, error: nil, storage: storage)))
            case .failure(let error):
                respond(.json(StorageConfigActionResponse(
                    ok: false,
                    error: error.localizedDescription,
                    storage: storageManager.status()
                )))
            }

        case ("GET", "/api/recording/status"):
            respond(.json(captureService.recordingStatus()))

        case ("GET", "/api/events/search"):
            let query = request.query["q"] ?? ""
            respond(.json(DetectionSearchResponse(
                query: query,
                results: eventStore.search(query)
            )))

        case ("GET", "/api/events/recent"):
            respond(.json(DetectionSearchResponse(
                query: "",
                results: eventStore.recent(limit: 20)
            )))

        case ("POST", "/api/events/reveal"):
            guard let id = request.query["id"], let event = eventStore.event(id: id) else {
                respond(.json(EventActionResponse(ok: false, error: "未找到该识别记录"), statusCode: 404))
                return
            }
            guard let path = event.videoPath else {
                respond(.json(EventActionResponse(ok: false, error: "该记录没有关联录像文件"), statusCode: 404))
                return
            }
            switch revealInFinder(path) {
            case .success:
                respond(.json(EventActionResponse(ok: true, error: nil)))
            case .failure(let error):
                respond(.json(EventActionResponse(ok: false, error: error.localizedDescription), statusCode: 404))
            }

        case ("POST", "/api/events/open"):
            guard let id = request.query["id"], let event = eventStore.event(id: id) else {
                respond(.json(EventActionResponse(ok: false, error: "未找到该识别记录"), statusCode: 404))
                return
            }
            guard let path = event.videoPath else {
                respond(.json(EventActionResponse(ok: false, error: "该记录没有关联录像文件"), statusCode: 404))
                return
            }
            switch openFile(path) {
            case .success:
                respond(.json(EventActionResponse(ok: true, error: nil)))
            case .failure(let error):
                respond(.json(EventActionResponse(ok: false, error: error.localizedDescription), statusCode: 404))
            }

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

enum AppActionError: LocalizedError {
    case fileNotFound
    case folderSelectionCancelled
    case storageFolderMustBeMountedVolume
    case folderPickerFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "录像文件不存在，可能是 NAS 未挂载或文件已移动"
        case .folderSelectionCancelled:
            return "已取消选择"
        case .storageFolderMustBeMountedVolume:
            return "保存位置必须位于 /Volumes 下的 NAS 或外接存储"
        case .folderPickerFailed(let detail):
            return detail.isEmpty ? "无法打开目录选择器" : "目录选择失败：\(detail)"
        }
    }
}
