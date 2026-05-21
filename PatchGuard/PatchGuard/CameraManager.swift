//
//  CameraManager.swift
//  PatchGuard
//

import AVFoundation
import Combine
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.patchguard", category: "CameraManager")

final class CameraManager: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var isCalibrated = false

    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private let ciContext = CIContext()
    nonisolated(unsafe) private var samplingInterval: TimeInterval = 1.0
    nonisolated(unsafe) private var lastFrameTime: TimeInterval = 0
    nonisolated(unsafe) private var captureDevice: AVCaptureDevice?

    // Tracks device orientation and physically rotates the pixel buffer via the connection
    nonisolated(unsafe) private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    nonisolated(unsafe) private var rotationObservation: NSKeyValueObservation?

    var onFrame: ((UIImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "pg.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "pg.camera.frames", qos: .userInitiated)

    func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureDevice = self.setupSession()
            self.session.startRunning()
        }
    }

    func calibrate() {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.captureDevice else { return }
            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(
                    duration: CMTime(value: 1, timescale: 500),
                    iso: AVCaptureDevice.currentISO
                ) { _ in
                    let d = device.exposureDuration
                    let shutter = d.value > 0 ? Int(Double(d.timescale) / Double(d.value)) : 0
                    logger.info("Calibrated — 1/\(shutter)s, ISO \(device.iso, format: .fixed(precision: 0))")
                    Task { @MainActor [weak self] in self?.isCalibrated = true }
                }
                device.unlockForConfiguration()
            } catch {
                logger.error("Calibration failed: \(error)")
            }
        }
    }

    @discardableResult
    nonisolated private func setupSession() -> AVCaptureDevice? {
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            return nil
        }

        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: frameQueue)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        // RotationCoordinator uses CoreMotion internally — fires immediately with current angle
        // and updates whenever the device rotates, keeping the pixel buffer upright automatically.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator

        let connection = output.connection(with: .video)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self, weak connection] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            self?.sessionQueue.async {
                if connection?.isVideoRotationAngleSupported(angle) == true {
                    connection?.videoRotationAngle = angle
                }
            }
        }

        return device
    }

    func setSamplingRate(_ fps: Int) {
        samplingInterval = 1.0 / Double(max(1, fps))
    }

    func start() {
        Task { @MainActor in isRunning = true }
    }

    func stop() {
        Task { @MainActor in isRunning = false }
    }

    func resetCalibration() {
        sessionQueue.async { [weak self] in
            guard let device = self?.captureDevice else { return }
            try? device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
            Task { @MainActor [weak self] in self?.isCalibrated = false }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrameTime >= samplingInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Pixel buffer is already upright — videoRotationAngle on the connection handles it.
        // Center-crop to 1080x1080; only the crop region is rendered by CIContext.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let e = ciImage.extent
        let side = min(e.width, e.height)
        let cropRect = CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side)
        guard let cgImage = ciContext.createCGImage(ciImage, from: cropRect) else { return }

        Task { @MainActor [weak self] in self?.onFrame?(UIImage(cgImage: cgImage)) }
    }
}
