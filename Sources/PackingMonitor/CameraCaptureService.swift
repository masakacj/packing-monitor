import AVFoundation
import CoreImage
import CoreMedia
import Foundation

/// Owns the live AVFoundation capture session.
///
/// The service keeps capture native on macOS and only emits a throttled JPEG
/// preview for the browser. Recording and Vision processing will consume the
/// same sample-buffer stream in later milestones without routing the original
/// video through the browser.
final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "packing-monitor.capture.session")
    private let sampleQueue = DispatchQueue(label: "packing-monitor.capture.samples")
    private let stateLock = NSLock()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let previewColorSpace = CGColorSpaceCreateDeviceRGB()

    private var videoOutput: AVCaptureVideoDataOutput?
    private var runningState = false
    private var activeDeviceID: String?
    private var activeDeviceName: String?
    private var latestPreviewJPEG: Data?
    private var capturedWidth: Int32 = 0
    private var capturedHeight: Int32 = 0
    private var lastFrameAt: Date?
    private var lastPreviewEncodedAt: TimeInterval = 0

    /// 2 FPS is enough for camera alignment / ROI setup and avoids wasting CPU
    /// on a browser preview while the native recording path stays full rate.
    private let previewInterval: TimeInterval = 0.5

    func startPreferredCamera() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraCaptureError.permissionRequired
        }

        let devices = AVCaptureDevice.devices(for: .video)
        guard let device = preferredDevice(from: devices) else {
            throw CameraCaptureError.noVideoDevice
        }

        try await start(device: device)
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }

                session.beginConfiguration()
                for input in session.inputs {
                    session.removeInput(input)
                }
                for output in session.outputs {
                    session.removeOutput(output)
                }
                session.commitConfiguration()
                videoOutput = nil

                stateLock.lock()
                runningState = false
                activeDeviceID = nil
                activeDeviceName = nil
                latestPreviewJPEG = nil
                capturedWidth = 0
                capturedHeight = 0
                lastFrameAt = nil
                lastPreviewEncodedAt = 0
                stateLock.unlock()

                continuation.resume()
            }
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

    func previewJPEG() -> Data? {
        stateLock.lock()
        let data = latestPreviewJPEG
        stateLock.unlock()
        return data
    }

    private func start(device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                if session.isRunning {
                    session.stopRunning()
                }

                session.beginConfiguration()
                do {
                    for input in session.inputs {
                        session.removeInput(input)
                    }
                    for output in session.outputs {
                        session.removeOutput(output)
                    }

                    // Prefer the highest practical preset the selected camera can
                    // deliver. The actual received frame dimensions are measured
                    // from CMSampleBuffer and exposed by the diagnostics API.
                    if session.canSetSessionPreset(.high) {
                        session.sessionPreset = .high
                    }

                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else {
                        throw CameraCaptureError.cannotAddInput
                    }
                    session.addInput(input)

                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    // Do not force BGRA. Apple recommends allowing a native pixel
                    // format when possible to avoid an unnecessary conversion.
                    output.setSampleBufferDelegate(self, queue: sampleQueue)
                    guard session.canAddOutput(output) else {
                        throw CameraCaptureError.cannotAddOutput
                    }
                    session.addOutput(output)
                    videoOutput = output

                    session.commitConfiguration()
                    session.startRunning()

                    stateLock.lock()
                    runningState = session.isRunning
                    activeDeviceID = device.uniqueID
                    activeDeviceName = device.localizedName
                    latestPreviewJPEG = nil
                    capturedWidth = 0
                    capturedHeight = 0
                    lastFrameAt = nil
                    lastPreviewEncodedAt = 0
                    stateLock.unlock()

                    continuation.resume()
                } catch {
                    session.commitConfiguration()
                    stateLock.lock()
                    runningState = false
                    stateLock.unlock()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func preferredDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        if let fuji = devices.first(where: { device in
            let haystack = "\(device.localizedName) \(device.manufacturer) \(device.modelID)".lowercased()
            return haystack.contains("fujifilm") || haystack.contains("fuji") || haystack.contains("x-t2")
        }) {
            return fuji
        }

        // External / virtual capture devices normally have an unspecified position.
        if let external = devices.first(where: { $0.position == .unspecified }) {
            return external
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

        guard shouldEncodePreview else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let jpeg = ciContext.jpegRepresentation(
            of: image,
            colorSpace: previewColorSpace,
            options: [.lossyCompressionQuality: 0.72]
        ) else {
            return
        }

        stateLock.lock()
        latestPreviewJPEG = jpeg
        stateLock.unlock()
    }
}

enum CameraCaptureError: LocalizedError {
    case permissionRequired
    case noVideoDevice
    case cannotAddInput
    case cannotAddOutput

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
        }
    }
}
