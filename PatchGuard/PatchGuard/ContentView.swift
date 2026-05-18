//
//  ContentView.swift
//  PatchGuard
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @StateObject private var gps = LocationManager()
    @State private var buffer = FrameBuffer()

    @Environment(\.scenePhase) private var scenePhase

    @State private var fps = 1
    @State private var frameCount = 0

    private static let fpsOptions = [1, 2, 5]

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 56)
                    .padding(.horizontal, 16)

                Spacer()

                controls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .onAppear(perform: setup)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, camera.isRunning else { return }
            handleBackgroundTransition()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(camera.isRunning ? Color.green : Color.gray)
                .frame(width: 9, height: 9)

            Text(camera.isRunning ? "\(frameCount) frames @ \(fps) FPS" : "Idle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            if camera.isRunning {
                Image(systemName: gps.location != nil ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(gps.location != nil ? Color.green : Color.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(Self.fpsOptions, id: \.self) { option in
                    Button("\(option) FPS") {
                        fps = option
                        camera.setSamplingRate(option)
                    }
                    .buttonStyle(SegmentButtonStyle(active: fps == option))
                }
            }

            Button(camera.isRunning ? "Stop" : "Start") {
                toggleCapture()
            }
            .buttonStyle(CaptureButtonStyle(capturing: camera.isRunning))
        }
    }

    private func setup() {
        gps.requestPermission()
        camera.configure()
        camera.setSamplingRate(fps)
    }

    private func toggleCapture() {
        if camera.isRunning {
            camera.onFrame = nil
            camera.stop()
            gps.stop()
            buffer.flush()  // send any remaining frames under the batch threshold
        } else {
            frameCount = 0
            camera.onFrame = { image in handleFrame(image) }
            gps.start()
            camera.start()
        }
    }

    private func handleBackgroundTransition() {
        camera.onFrame = nil
        camera.stop()
        gps.stop()
        buffer.clear()
    }

    private func handleFrame(_ image: UIImage) {
        // Snapshot all main-actor values before jumping to background
        let capturedAt  = iso8601.string(from: Date())
        let loc         = gps.location
        let hdg         = gps.heading
        let latitude    = loc?.coordinate.latitude  ?? 0
        let longitude   = loc?.coordinate.longitude ?? 0
        let altitude    = loc?.altitude
        let gpsAccuracy = loc.flatMap { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : nil }
        let heading     = hdg.flatMap { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading }
        let filename    = "frame_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        frameCount += 1

        let buf = buffer
        Task.detached(priority: .utility) {
            guard let jpeg = image.jpegData(compressionQuality: 0.7) else { return }
            let metadata = ImageMetadata(
                filename: filename,
                latitude: latitude,
                longitude: longitude,
                captured_at: capturedAt,
                heading: heading,
                altitude: altitude,
                gps_accuracy: gpsAccuracy
            )
            await buf.add(jpeg: jpeg, metadata: metadata)
        }
    }
}

struct SegmentButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 80, height: 40)
            .background(active ? Color.white : Color.white.opacity(0.22))
            .foregroundStyle(active ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CaptureButtonStyle: ButtonStyle {
    let capturing: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(capturing ? Color.red : Color.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ContentView()
}
