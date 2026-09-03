import CoreVideo
import Foundation
import Vision

final class LabelRecognitionEngine {
    var onConfirmed: ((RecognitionHit) -> Void)?

    private let lock = NSLock()
    private var candidateStates: [String: CandidateState] = [:]
    private var lastEmittedAt: [String: TimeInterval] = [:]
    private var lastBarcodeAnalysisAt: TimeInterval = 0
    private var lastOCRAnalysisAt: TimeInterval = 0
    private var totalConfirmed = 0
    private var lastHit: RecognitionHit?
    private var lastError: String?

    private let barcodeInterval: TimeInterval = 0.40
    private let ocrInterval: TimeInterval = 1.50
    private let candidateWindow: TimeInterval = 3.0
    private let duplicateSuppressInterval: TimeInterval = 120.0

    func status() -> RecognitionStatusResponse {
        lock.lock()
        defer { lock.unlock() }
        return RecognitionStatusResponse(
            enabled: true,
            totalConfirmed: totalConfirmed,
            lastHit: lastHit,
            lastError: lastError
        )
    }

    func resetSession() {
        lock.lock()
        candidateStates.removeAll()
        lastBarcodeAnalysisAt = 0
        lastOCRAnalysisAt = 0
        lastError = nil
        lock.unlock()
    }

    func process(pixelBuffer: CVPixelBuffer, capturedAt: Date) {
        let uptime = ProcessInfo.processInfo.systemUptime
        var runBarcode = false
        var runOCR = false

        lock.lock()
        if uptime - lastBarcodeAnalysisAt >= barcodeInterval {
            lastBarcodeAnalysisAt = uptime
            runBarcode = true
        }
        if uptime - lastOCRAnalysisAt >= ocrInterval {
            lastOCRAnalysisAt = uptime
            runOCR = true
        }
        lock.unlock()

        guard runBarcode || runOCR else { return }

        if runBarcode, recognizeBarcode(pixelBuffer: pixelBuffer, capturedAt: capturedAt, uptime: uptime) {
            return
        }

        if runOCR {
            recognizeText(pixelBuffer: pixelBuffer, capturedAt: capturedAt, uptime: uptime)
        }
    }

    @discardableResult
    private func recognizeBarcode(pixelBuffer: CVPixelBuffer, capturedAt: Date, uptime: TimeInterval) -> Bool {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
            let observations = request.results as? [VNBarcodeObservation] ?? []
            let candidates = observations.compactMap { observation -> RecognitionCandidate? in
                guard let raw = observation.payloadStringValue,
                      let code = normalizedTrackingNumber(raw)
                else { return nil }

                let symbology = String(describing: observation.symbology)
                let area = Double(observation.boundingBox.width * observation.boundingBox.height)
                var score = area * 100.0 + Double(code.count)
                let lower = symbology.lowercased()
                if lower.contains("code128") || lower.contains("code 128") { score += 30 }
                if lower.contains("qr") || lower.contains("pdf417") || lower.contains("data") { score += 15 }
                if lower.contains("ean") || lower.contains("upc") { score -= 10 }

                return RecognitionCandidate(
                    trackingNumber: code,
                    rawValue: raw,
                    source: "barcode",
                    symbology: symbology,
                    confidence: Double(observation.confidence),
                    boundingBox: observation.boundingBox,
                    score: score,
                    requiredConfirmations: 2
                )
            }

            guard let best = candidates.max(by: { $0.score < $1.score }) else { return false }
            return consider(best, capturedAt: capturedAt, uptime: uptime)
        } catch {
            setError("Barcode Vision error: \(error.localizedDescription)")
            return false
        }
    }

    private func recognizeText(pixelBuffer: CVPixelBuffer, capturedAt: Date, uptime: TimeInterval) {
        if #available(macOS 10.15, *) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var candidates: [RecognitionCandidate] = []

                for observation in observations {
                    guard let recognized = observation.topCandidates(1).first else { continue }
                    for code in trackingCandidates(from: recognized.string) {
                        let area = Double(observation.boundingBox.width * observation.boundingBox.height)
                        let score = area * 50.0 + Double(code.count) + Double(recognized.confidence) * 20.0
                        candidates.append(RecognitionCandidate(
                            trackingNumber: code,
                            rawValue: recognized.string,
                            source: "ocr",
                            symbology: nil,
                            confidence: Double(recognized.confidence),
                            boundingBox: observation.boundingBox,
                            score: score,
                            requiredConfirmations: 2
                        ))
                    }
                }

                if let best = candidates.max(by: { $0.score < $1.score }) {
                    _ = consider(best, capturedAt: capturedAt, uptime: uptime)
                }
            } catch {
                setError("OCR Vision error: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func consider(_ candidate: RecognitionCandidate, capturedAt: Date, uptime: TimeInterval) -> Bool {
        var emittedHit: RecognitionHit?

        lock.lock()
        let key = candidate.trackingNumber
        if let previousEmit = lastEmittedAt[key], uptime - previousEmit < duplicateSuppressInterval {
            lock.unlock()
            return false
        }

        var state = candidateStates[key] ?? CandidateState(count: 0, lastSeenAt: 0)
        if uptime - state.lastSeenAt > candidateWindow {
            state.count = 0
        }
        state.count += 1
        state.lastSeenAt = uptime
        candidateStates[key] = state

        if state.count >= candidate.requiredConfirmations {
            let box = candidate.boundingBox
            let hit = RecognitionHit(
                trackingNumber: candidate.trackingNumber,
                rawValue: candidate.rawValue,
                source: candidate.source,
                symbology: candidate.symbology,
                confidence: candidate.confidence,
                detectedAt: capturedAt,
                boundingBox: NormalizedRect(
                    x: Double(box.origin.x),
                    y: Double(box.origin.y),
                    width: Double(box.size.width),
                    height: Double(box.size.height)
                )
            )
            lastEmittedAt[key] = uptime
            candidateStates[key] = CandidateState(count: 0, lastSeenAt: uptime)
            totalConfirmed += 1
            lastHit = hit
            lastError = nil
            emittedHit = hit
        }
        lock.unlock()

        if let hit = emittedHit {
            onConfirmed?(hit)
            return true
        }
        return false
    }

    private func trackingCandidates(from text: String) -> [String] {
        let upper = text.uppercased()
        var values: [String] = []

        if let whole = normalizedTrackingNumber(upper) {
            values.append(whole)
        }

        let pieces = upper.components(separatedBy: CharacterSet.alphanumerics.inverted)
        for piece in pieces {
            if let value = normalizedTrackingNumber(piece), !values.contains(value) {
                values.append(value)
            }
        }
        return values
    }

    private func normalizedTrackingNumber(_ raw: String) -> String? {
        let upper = raw.uppercased()
        let scalars = upper.unicodeScalars.filter { scalar in
            let value = scalar.value
            return (value >= 48 && value <= 57) || (value >= 65 && value <= 90)
        }
        let code = String(String.UnicodeScalarView(scalars))
        guard code.count >= 8 && code.count <= 32 else { return nil }

        let digits = code.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.count
        let letters = code.count - digits
        guard digits >= 8 || (digits >= 6 && letters >= 2) else { return nil }
        guard Set(code).count > 1 else { return nil }
        return code
    }

    private func setError(_ message: String) {
        lock.lock()
        lastError = message
        lock.unlock()
    }
}

private struct RecognitionCandidate {
    let trackingNumber: String
    let rawValue: String
    let source: String
    let symbology: String?
    let confidence: Double
    let boundingBox: CGRect
    let score: Double
    let requiredConfirmations: Int
}

private struct CandidateState {
    var count: Int
    var lastSeenAt: TimeInterval
}
