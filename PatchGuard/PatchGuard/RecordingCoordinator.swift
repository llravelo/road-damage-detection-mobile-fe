//
//  RecordingCoordinator.swift
//  PatchGuard
//

import AVFoundation
import Combine
import CoreLocation
import UIKit

@MainActor
final class RecordingCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isCalibrated = false
    @Published private(set) var hasGPS = false
    @Published private(set) var frameCount = 0
    @Published var fps = 1 {
        didSet { camera.setSamplingRate(fps) }
    }

    var cameraSession: AVCaptureSession { camera.session }

    private let camera = CameraManager()
    private let gps    = LocationManager()
    private let buffer = FrameBuffer()

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init() {
        camera.$isCalibrated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isCalibrated)

        gps.$location
            .map { $0 != nil }
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasGPS)
    }

    func setup() {
        gps.requestPermission()
        camera.configure()
        camera.setSamplingRate(fps)
    }

    func calibrate()        { camera.calibrate() }
    func resetCalibration() { camera.resetCalibration() }

    func startRecording() {
        frameCount = 0
        isRunning  = true
        gps.start()
        camera.onFrame = { [weak self] image in self?.handleFrame(image) }
    }

    func stopRecording() {
        camera.onFrame = nil
        isRunning = false
        gps.stop()
        buffer.flush()
    }

    func handleBackground() {
        camera.onFrame = nil
        isRunning = false
        gps.stop()
        buffer.clear()
    }

    private func handleFrame(_ image: UIImage) {
        let capturedAt = iso8601.string(from: Date())
        let loc        = gps.location
        let hdg        = gps.heading
        let metadata   = ImageMetadata(
            filename:     "frame_\(Int(Date().timeIntervalSince1970 * 1000)).jpg",
            latitude:     loc?.coordinate.latitude  ?? 0,
            longitude:    loc?.coordinate.longitude ?? 0,
            captured_at:  capturedAt,
            heading:      hdg.flatMap { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading },
            altitude:     loc?.altitude,
            gps_accuracy: loc.flatMap { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil }
        )
        frameCount += 1
        let buf = buffer
        Task.detached(priority: .utility) {
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
            await buf.add(jpeg: jpeg, metadata: metadata)
        }
    }
}
