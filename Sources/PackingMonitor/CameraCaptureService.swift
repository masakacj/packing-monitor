import AVFoundation
import CoreImage
import CoreMedia
import Foundation

/// Owns the live AVFoundation capture session, lightweight browser preview,
/// Vision recognition, and direct-to-NAS segmented recording.
final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "packing-monitor.capture.session")
    private let sampleQueue = DispatchQueue(label: "packing-monitor.capture.samples")
    private let stateLock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let previewColorSpace = CGColorSpaceCreateDeviceRGB()
    private let movieOutput = AVCaptureMovieFileOutput()

    private let storage: StorageManager
    private let eventStore: DetectionEventStore
    private let recognitionEngine: LabelRecognitionEngine

    private var videoOutput: AVCaptureVideoDataOutput?
    private var runningState = false
    private var activeDeviceID: String?
    private var activeDeviceName: String?
    private var latestPreviewJPEG: Data?
    private var capturedWidth: Int32 = 0
    private var capturedHeight: Int32 = 0
    private var lastFrameAt: Date?
    private var lastPreviewEncodedAt: TimeInterval = 0

    private var shouldContinueRecording = false
    private var recordingState = false
    private var currentRecordingPath: String?
    private var currentSegmentStartedAt: Date?
    private var lastRecordingError: String?

    /// The browser preview is deliberately lower rate than the native capture
    /// path. 8 FPS is smooth enough for setup while leaving CPU for Vision.
    private let previewInterval: TimeInterval = 0.125
    private let previewMaxWidth: CGFloat = 960

    init(storage: StorageManager, eventStore: DetectionEventStore) {
        self.storage = storage
        self.eventStore = eventStore
        self.recognitionEngine = LabelRecognitionEngine()
        super.init()
        self.recognitionEngine.onConfirmed = { [weak self] hit in
            self?.handleConfirmedRecognition(hit)
        }
    }

    func startPreferredCamera(completion: @escaping (Result<Void, Error>) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            completion(.failure(CameraCaptureError.permissionRequired))
            return
        }

        let devices = AVCaptureDevice.devices(for: .video)
        guard let device = preferredDevice(from: devices) else {
            completion(.failure(CameraCaptureError.noVideoDevice))
            return
        }

        start(deviceID: device.uniqueID, completion: completion)
    }

    func start(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            completion(.failure(CameraCaptureError.permissionRequired))
            return
        }
        configureAndStart(deviceID: deviceID, completion: completion)
    }

    func stop(completion: (() -> Void)? = nil) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }

            self.shouldContinueRecording = false
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.session.beginConfiguration()
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.session.commitConfiguration()
            self.videoOutput = nil

            self.stateLock.lock()
            self.runningState = false
            self.activeDeviceID = nil
            self.activeDeviceName = nil
            self.latestPreviewJPEG = nil
            self.capturedWidth = 0
            self.capturedHeight = 0
            self.lastFrameAt = nil
            self.lastPreviewEncodedAt = 0
            self.recordingState = false
            self.currentRecordingPath = nil
            self.currentSegmentStartedAt = nil
            self.stateLock.unlock()

            self.recognitionEngine.resetSession()
            completion?()
        }
    }

    func status() -> CameraCaptureStatusResponse {
        stateLock.lock()
        let response = CameraCaptureStatusResponse(
            running: runningState,
            deviceID: activeDeviceID,
            deviceName: activeDeviceName,
            capturedWidth: capturedWidth,
            capturedHeight: capturedHeight,
            lastFrameAt: lastFrameAt,
            previewAvailable: latestPreviewJPEG != nil
        )
        stateLock.unlock()
        return response
    }

    func recognitionStatus() -> RecognitionStatusResponse {
        return recognitionEngine.status()
    }

    func recordingStatus() -> RecordingStatusResponse {
        stateLock.lock()
        let recording = recordingState
        let path = currentRecordingPath
        let started = currentSegmentStartedAt
        let error = lastRecordingError
        stateLock.unlock()

        let duration = started.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        return RecordingStatusResponse(
            recording: recording,
            currentPath: path,
            segmentStartedAt: started,
            segmentDurationSeconds: duration,
            lastError: error
        )
    }

    func refreshRecordingConfiguration() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            if self.storage.recordingEnabled {
                self.shouldContinueRecording = true
                if !self.movieOutput.isRecording {
                    self.startNextRecordingSegment()
                }
            } else {
                self.shouldContinueRecording = false
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
            }
        }
    }

    func previewJPEG() -> Data? {
        stateLock.lock()
        let data = latestPreviewJPEG
        stateLock.unlock()
        return data
    }

    private func configureAndStart(deviceID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(CameraCaptureError.noVideoDevice))
                return
            }

            let devices = AVCaptureDevice.devices(for: .video)
            guard let device = devices.first(where: { $0.uniqueID == deviceID }) else {
                completion(.failure(CameraCaptureError.noVideoDevice))
                return
            }

            self.shouldContinueRecording = false
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.session.beginConfiguration()
            do {
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }
                for output in self.session.outputs {
                    self.session.removeOutput(output)
                }

                if self.session.canSetSessionPreset(.high) {
                    self.session.sessionPreset = .high
                }

                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    throw CameraCaptureError.cannotAddInput
                }
                self.session.addInput(input)

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: self.sampleQueue)
                guard self.session.canAddOutput(output) else {
                    throw CameraCaptureError.cannotAddOutput
                }
                self.session.addOutput(output)
                self.videoOutput = output

                guard self.session.canAddOutput(self.movieOutput) else {
                    throw CameraCaptureError.cannotAddMovieOutput
                }
                self.session.addOutput(self.movieOutput)

                self.session.commitConfiguration()
                self.session.startRunning()

                self.stateLock.lock()
                self.runningState = self.session.isRunning
                self.activeDeviceID = device.uniqueID
                self.activeDeviceName = device.localizedName
                self.latestPreviewJPEG = nil
                self.capturedWidth = 0
                self.capturedHeight = 0
                self.lastFrameAt = nil
                self.lastPreviewEncodedAt = 0
                self.recordingState = false
                self.currentRecordingPath = nil
                self.currentSegmentStartedAt = nil
                self.lastRecordingError = nil
                self.stateLock.unlock()

                self.recognitionEngine.resetSession()

                if self.storage.recordingEnabled {
                    self.shouldContinueRecording = true
                    self.startNextRecordingSegment()
                }

                completion(.success(()))
            } catch {
                self.session.commitConfiguration()
                self.stateLock.lock()
                self.runningState = false
                self.stateLock.unlock()
                completion(.failure(error))
            }
        }
    }

    private func startNextRecordingSegment() {
        guard session.isRunning, shouldContinueRecording, storage.recordingEnabled, !movieOutput.isRecording else { return }

        do {
            guard let url = try storage.nextRecordingURL() else {
                shouldContinueRecording = false
                return
            }

            movieOutput.maxRecordedDuration = CMTime(
                seconds: Double(storage.segmentMinutes * 60),
                preferredTimescale: 600
            )
            stateLock.lock()
            lastRecordingError = nil
            stateLock.unlock()
            movieOutput.startRecording(to: url, recordingDelegate: self)
        } catch {
            stateLock.lock()
            lastRecordingError = error.localizedDescription
            recordingState = false
            currentRecordingPath = nil
            currentSegmentStartedAt = nil
            stateLock.unlock()
        }
    }

    private func preferredDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        if let capture = devices.first(where: { device in
            let haystack = "\(device.localizedName) \(device.manufacturer) \(device.modelID)".lowercased()
            let looksLikeCapture = haystack.contains("capture") ||
                haystack.contains("uvc") ||
                haystack.contains("hdmi") ||
                haystack.contains("usb3") ||
                haystack.contains("usb 3")
            let isFujiVirtual = haystack.contains("x webcam") || haystack.contains("fujifilm x webcam")
            return looksLikeCapture && !isFujiVirtual
        }) {
            return capture
        }

        if let external = devices.first(where: { device in
            let haystack = "\(device.localizedName) \(device.manufacturer) \(device.modelID)".lowercased()
            return device.position == .unspecified && !haystack.contains("x webcam")
        }) {
            return external
        }

        if let fuji = devices.first(where: { device in
            let haystack = "\(device.localizedName) \(device.manufacturer) \(device.modelID)".lowercased()
            return haystack.contains("fujifilm") || haystack.contains("fuji") || haystack.contains("x-t2")
        }) {
            return fuji
        }

        return devices.first
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else {
            return
        }

        let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime

        stateLock.lock()
        capturedWidth = dimensions.width
        capturedHeight = dimensions.height
        lastFrameAt = now
        let shouldEncodePreview = uptime - lastPreviewEncodedAt >= previewInterval
        if shouldEncodePreview {
            lastPreviewEncodedAt = uptime
        }
        stateLock.unlock()

        recognitionEngine.process(pixelBuffer: pixelBuffer, capturedAt: now)

        guard shouldEncodePreview else { return }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = max(sourceImage.extent.width, 1)
        let scale = min(1, previewMaxWidth / width)
        let previewImage = scale < 1
            ? sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : sourceImage

        guard let jpeg = ciContext.jpegRepresentation(
            of: previewImage,
            colorSpace: previewColorSpace,
            options: [:]
        ) else {
            return
        }

        stateLock.lock()
        latestPreviewJPEG = jpeg
        stateLock.unlock()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        stateLock.lock()
        recordingState = true
        currentRecordingPath = fileURL.path
        currentSegmentStartedAt = Date()
        lastRecordingError = nil
        stateLock.unlock()
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let continueRecording = session.isRunning && shouldContinueRecording && storage.recordingEnabled

        var benignDurationEnd = false
        if let nsError = error as NSError? {
            benignDurationEnd = nsError.domain == AVFoundationErrorDomain &&
                nsError.code == AVError.Code.maximumDurationReached.rawValue
        }

        stateLock.lock()
        recordingState = false
        currentRecordingPath = nil
        currentSegmentStartedAt = nil
        if let error = error, !benignDurationEnd {
            lastRecordingError = error.localizedDescription
        }
        stateLock.unlock()

        if continueRecording {
            sessionQueue.async { [weak self] in
                self?.startNextRecordingSegment()
            }
        }
    }

    private func handleConfirmedRecognition(_ hit: RecognitionHit) {
        if eventStore.hasRecentDuplicate(trackingNumber: hit.trackingNumber) {
            return
        }

        stateLock.lock()
        let deviceName = activeDeviceName
        let videoPath = currentRecordingPath
        let segmentStartedAt = currentSegmentStartedAt
        stateLock.unlock()

        let offset = segmentStartedAt.map { max(0, hit.detectedAt.timeIntervalSince($0)) }
        let event = DetectionEvent(
            id: UUID().uuidString,
            trackingNumber: hit.trackingNumber,
            rawValue: hit.rawValue,
            source: hit.source,
            symbology: hit.symbology,
            confidence: hit.confidence,
            detectedAt: hit.detectedAt,
            boundingBox: hit.boundingBox,
            deviceName: deviceName,
            videoPath: videoPath,
            segmentStartedAt: segmentStartedAt,
            offsetSeconds: offset
        )
        _ = eventStore.record(event)
    }
}

enum CameraCaptureError: LocalizedError {
    case permissionRequired
    case noVideoDevice
    case cannotAddInput
    case cannotAddOutput
    case cannotAddMovieOutput

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Camera permission is required before capture can start."
        case .noVideoDevice:
            return "No AVFoundation video device is available."
        case .cannotAddInput:
            return "AVFoundation could not add the selected camera input."
        case .cannotAddOutput:
            return "AVFoundation could not add the video data output."
        case .cannotAddMovieOutput:
            return "AVFoundation could not add the movie recording output."
        }
    }
}
