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
        ZStack {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()

            // Dark vignette outside the crop square with viewfinder corners
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let rect = CGRect(
                    x: (geo.size.width - side) / 2,
                    y: (geo.size.height - side) / 2,
                    width: side,
                    height: side
                )

                ZStack {
                    Canvas { context, size in
                        var path = Path(CGRect(origin: .zero, size: size))
                        path.addRect(rect)
                        context.fill(path, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
                    }

                    ViewfinderCorners(rect: rect)
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                    .padding(.top, 56)
                    .padding(.horizontal, 20)

                Spacer()

                controls
                    .padding(.horizontal, 32)
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
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(camera.isRunning ? Color.red : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(camera.isRunning ? "\(frameCount) frames" : "Ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Image(systemName: gps.location != nil ? "location.fill" : "location.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(gps.location != nil ? .green : .orange)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var controls: some View {
        VStack(spacing: 24) {
            if !camera.isCalibrated {
                Button("Calibrate") {
                    camera.calibrate()
                }
                .buttonStyle(CalibrateButtonStyle())
            } else {
                HStack(spacing: 8) {
                    ForEach(Self.fpsOptions, id: \.self) { option in
                        Button("\(option) FPS") {
                            fps = option
                            camera.setSamplingRate(option)
                        }
                        .buttonStyle(FPSButtonStyle(active: fps == option))
                    }
                }

                ZStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        Button(action: toggleCapture) {
                            ZStack {
                                Circle()
                                    .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                                    .frame(width: 80, height: 80)

                                if camera.isRunning {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.red)
                                        .frame(width: 30, height: 30)
                                } else {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 62, height: 62)
                                }
                            }
                            .animation(.easeInOut(duration: 0.15), value: camera.isRunning)
                        }
                        Spacer()
                    }

                    Button("Recalibrate") {
                        camera.resetCalibration()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(camera.isRunning ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: camera.isRunning)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: camera.isCalibrated)
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
            buffer.flush()
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
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
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

struct CalibrateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 160, height: 48)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FPSButtonStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 70, height: 36)
            .background(active ? Color.white : Color.white.opacity(0.2))
            .foregroundStyle(active ? Color.black : Color.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ViewfinderCorners: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            let length: CGFloat = 28
            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                (CGPoint(x: rect.minX, y: rect.minY + length),
                 CGPoint(x: rect.minX, y: rect.minY),
                 CGPoint(x: rect.minX + length, y: rect.minY)),
                (CGPoint(x: rect.maxX - length, y: rect.minY),
                 CGPoint(x: rect.maxX, y: rect.minY),
                 CGPoint(x: rect.maxX, y: rect.minY + length)),
                (CGPoint(x: rect.minX, y: rect.maxY - length),
                 CGPoint(x: rect.minX, y: rect.maxY),
                 CGPoint(x: rect.minX + length, y: rect.maxY)),
                (CGPoint(x: rect.maxX - length, y: rect.maxY),
                 CGPoint(x: rect.maxX, y: rect.maxY),
                 CGPoint(x: rect.maxX, y: rect.maxY - length)),
            ]
            for (a, corner, b) in corners {
                var path = Path()
                path.move(to: a)
                path.addLine(to: corner)
                path.addLine(to: b)
                context.stroke(path, with: .color(.white.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }
}

#Preview {
    ContentView()
}
