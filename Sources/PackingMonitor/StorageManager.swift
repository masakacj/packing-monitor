import Foundation

final class StorageManager {
    private let defaults: UserDefaults
    private let lock = NSLock()

    private let rootPathKey = "storage.rootPath"
    private let recordingEnabledKey = "storage.recordingEnabled"
    private let segmentMinutesKey = "storage.segmentMinutes"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: recordingEnabledKey) == nil {
            defaults.set(true, forKey: recordingEnabledKey)
        }
        if defaults.object(forKey: segmentMinutesKey) == nil {
            defaults.set(5, forKey: segmentMinutesKey)
        }
    }

    var rootPath: String? {
        lock.lock()
        defer { lock.unlock() }
        let value = defaults.string(forKey: rootPathKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    var recordingEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return defaults.bool(forKey: recordingEnabledKey)
    }

    var segmentMinutes: Int {
        lock.lock()
        defer { lock.unlock() }
        return max(1, min(60, defaults.integer(forKey: segmentMinutesKey)))
    }

    func configure(rootPath: String, recordingEnabled: Bool, segmentMinutes: Int) -> Result<StorageStatusResponse, Error> {
        let normalized = normalize(path: rootPath)
        let minutes = max(1, min(60, segmentMinutes))

        if !normalized.isEmpty {
            guard normalized == "/Volumes" || normalized.hasPrefix("/Volumes/") else {
                return .failure(StorageError.nasPathRequired)
            }

            do {
                try prepareRoot(normalized)
            } catch {
                return .failure(error)
            }
        }

        lock.lock()
        if normalized.isEmpty {
            defaults.removeObject(forKey: rootPathKey)
        } else {
            defaults.set(normalized, forKey: rootPathKey)
        }
        defaults.set(recordingEnabled, forKey: recordingEnabledKey)
        defaults.set(minutes, forKey: segmentMinutesKey)
        lock.unlock()

        return .success(status())
    }

    func status() -> StorageStatusResponse {
        let path = rootPath
        let enabled = recordingEnabled
        let minutes = segmentMinutes
        let volumes = mountedVolumes()

        guard let path = path else {
            return StorageStatusResponse(
                rootPath: nil,
                configured: false,
                available: false,
                writable: false,
                recordingEnabled: enabled,
                segmentMinutes: minutes,
                mountedVolumes: volumes,
                error: "请配置已挂载的 NAS 路径，例如 /Volumes/NAS/PackingMonitor"
            )
        }

        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let available = fm.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        var writable = false
        var errorMessage: String?

        if available {
            do {
                try verifyWritable(path)
                writable = true
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = "NAS 路径当前不可用，请确认共享目录已经挂载"
        }

        return StorageStatusResponse(
            rootPath: path,
            configured: true,
            available: available,
            writable: writable,
            recordingEnabled: enabled,
            segmentMinutes: minutes,
            mountedVolumes: volumes,
            error: errorMessage
        )
    }

    func mountedVolumes() -> [String] {
        let root = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url -> String? in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            return url.path
        }.sorted()
    }

    func nextRecordingURL(at date: Date = Date()) throws -> URL? {
        guard recordingEnabled, let root = rootPath else { return nil }
        try prepareRoot(root)

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let day = dayFormatter.string(from: date)

        let fileFormatter = DateFormatter()
        fileFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = fileFormatter.string(from: date)

        let directory = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("video", isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        return directory.appendingPathComponent("packing-\(stamp).mov")
    }

    func indexURL() throws -> URL? {
        guard let root = rootPath else { return nil }
        try prepareRoot(root)
        return URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("index", isDirectory: true)
            .appendingPathComponent("events.jsonl", isDirectory: false)
    }

    private func normalize(path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func prepareRoot(_ root: String) throws {
        guard root == "/Volumes" || root.hasPrefix("/Volumes/") else {
            throw StorageError.nasPathRequired
        }

        let components = root.split(separator: "/")
        guard components.count >= 2 else {
            throw StorageError.shareNotMounted
        }

        let shareRoot = "/Volumes/\(components[1])"
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: shareRoot, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw StorageError.shareNotMounted
        }

        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("video", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: rootURL.appendingPathComponent("index", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
        try verifyWritable(root)
    }

    private func verifyWritable(_ root: String) throws {
        let testURL = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(".packing-monitor-write-test-\(UUID().uuidString)")
        let data = Data("ok".utf8)
        do {
            try data.write(to: testURL, options: .atomic)
            try FileManager.default.removeItem(at: testURL)
        } catch {
            try? FileManager.default.removeItem(at: testURL)
            throw StorageError.notWritable(error.localizedDescription)
        }
    }
}

enum StorageError: LocalizedError {
    case nasPathRequired
    case shareNotMounted
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .nasPathRequired:
            return "为避免占用 Mac 本地硬盘，存储路径必须位于 /Volumes 下的 NAS 挂载目录"
        case .shareNotMounted:
            return "NAS 共享目录尚未挂载"
        case .notWritable(let detail):
            return "NAS 路径不可写：\(detail)"
        }
    }
}
