import AVFoundation
import CoreImage
import CoreMedia
import Foundation

/// Owns the live AVFoundation capture session.
///
/// This implementation intentionally avoids Swift concurrency so it can be
/// built with the Swift toolchain available on macOS Catalina/Xcode 12.
final class CameraCaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
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
    private let previewMaxWidth: CGFloat = 960

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
            self.stateLock.unlock()

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
                self.stateLock.unlock()

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

    private func preferredDevice(from devices: [AVCaptureDevice]) -> AVCaptureDevice? {
        // Prefer USB/HDMI capture devices for packing-monitor use. Virtual
        // webcam drivers such as FUJIFILM X Webcam can remain installed but
        // should not beat a real capture card when no saved selection exists.
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
