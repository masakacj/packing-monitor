import Foundation

final class DetectionEventStore {
    private let storage: StorageManager
    private let queue = DispatchQueue(label: "packing-monitor.events")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(storage: StorageManager) {
        self.storage = storage
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func record(_ event: DetectionEvent) -> Result<Void, Error> {
        return queue.sync {
            do {
                guard let url = try storage.indexURL() else {
                    throw DetectionEventStoreError.storageNotConfigured
                }

                let data = try encoder.encode(event)
                var line = data
                line.append(0x0A)

                if !FileManager.default.fileExists(atPath: url.path) {
                    try line.write(to: url, options: .atomic)
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { handle.closeFile() }
                    handle.seekToEndOfFile()
                    handle.write(line)
                }
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    func search(_ query: String, limit: Int = 50) -> [DetectionEvent] {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return [] }

        return queue.sync {
            guard let indexURL = try? storage.indexURL() else { return [] }
            guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else { return [] }
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            var matches: [DetectionEvent] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let lineData = String(line).data(using: .utf8),
                      let event = try? decoder.decode(DetectionEvent.self, from: lineData)
                else { continue }

                let eventCode = normalize(event.trackingNumber)
                if eventCode == normalized || eventCode.contains(normalized) || normalized.contains(eventCode) {
                    matches.append(event)
                }
            }

            return Array(matches.sorted { $0.detectedAt > $1.detectedAt }.prefix(max(1, min(200, limit))))
        }
    }

    func recent(limit: Int = 20) -> [DetectionEvent] {
        return queue.sync {
            guard let indexURL = try? storage.indexURL() else { return [] }
            guard let data = try? Data(contentsOf: indexURL), !data.isEmpty else { return [] }
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            var events: [DetectionEvent] = []
            for line in text.split(separator: "\n", omittingEmptySubsequences: true).suffix(max(1, min(200, limit * 2))) {
                guard let lineData = String(line).data(using: .utf8),
                      let event = try? decoder.decode(DetectionEvent.self, from: lineData)
                else { continue }
                events.append(event)
            }
            return Array(events.sorted { $0.detectedAt > $1.detectedAt }.prefix(max(1, min(200, limit))))
        }
    }

    func event(id: String) -> DetectionEvent? {
        return queue.sync {
            guard let indexURL = try? storage.indexURL() else { return nil }
            guard let data = try? Data(contentsOf: indexURL),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                guard let lineData = String(line).data(using: .utf8),
                      let event = try? decoder.decode(DetectionEvent.self, from: lineData)
                else { continue }
                if event.id == id { return event }
            }
            return nil
        }
    }

    func hasRecentDuplicate(trackingNumber: String, within seconds: TimeInterval = 120) -> Bool {
        let normalized = normalize(trackingNumber)
        guard !normalized.isEmpty else { return false }
        let cutoff = Date().addingTimeInterval(-seconds)

        return recent(limit: 30).contains { event in
            event.detectedAt >= cutoff && normalize(event.trackingNumber) == normalized
        }
    }

    private func normalize(_ value: String) -> String {
        let upper = value.uppercased()
        let allowed = upper.unicodeScalars.filter { scalar in
            let v = scalar.value
            return (v >= 48 && v <= 57) || (v >= 65 && v <= 90)
        }
        return String(String.UnicodeScalarView(allowed))
    }
}

enum DetectionEventStoreError: LocalizedError {
    case storageNotConfigured

    var errorDescription: String? {
        switch self {
        case .storageNotConfigured:
            return "NAS 存储尚未配置，无法写入面单索引"
        }
    }
}
