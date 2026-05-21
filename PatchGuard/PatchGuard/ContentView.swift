//
//  ContentView.swift
//  PatchGuard
//

import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = RecordingCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    private static let fpsOptions = [1, 2, 5]

    var body: some View {
        ZStack {
            CameraPreviewView(session: coordinator.cameraSession)
                .ignoresSafeArea()

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
        .onAppear { coordinator.setup() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background, coordinator.isRunning else { return }
            coordinator.handleBackground()
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(coordinator.isRunning ? Color.red : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(coordinator.isRunning ? "\(coordinator.frameCount) frames" : "Ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Image(systemName: coordinator.hasGPS ? "location.fill" : "location.slash.fill")
                .font(.system(size: 14))
                .foregroundStyle(coordinator.hasGPS ? .green : .orange)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 24) {
            if !coordinator.isCalibrated {
                Button("Calibrate") { coordinator.calibrate() }
                    .buttonStyle(CalibrateButtonStyle())
            } else {
                HStack(spacing: 8) {
                    ForEach(Self.fpsOptions, id: \.self) { option in
                        Button("\(option) FPS") { coordinator.fps = option }
                            .buttonStyle(FPSButtonStyle(active: coordinator.fps == option))
                    }
                }

                ZStack(alignment: .leading) {
                    HStack {
                        Spacer()
                        recordButton
                        Spacer()
                    }

                    Button("Recalibrate") { coordinator.resetCalibration() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .opacity(coordinator.isRunning ? 0 : 1)
                        .animation(.easeInOut(duration: 0.15), value: coordinator.isRunning)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.isCalibrated)
    }

    private var recordButton: some View {
        Button {
            coordinator.isRunning ? coordinator.stopRecording() : coordinator.startRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.4), lineWidth: 3)
                    .frame(width: 80, height: 80)
                if coordinator.isRunning {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.red)
                        .frame(width: 30, height: 30)
                } else {
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: coordinator.isRunning)
        }
    }
}

// MARK: - Button Styles

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

// MARK: - Viewfinder

struct ViewfinderCorners: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            let length: CGFloat = 28
            let corners: [(CGPoint, CGPoint, CGPoint)] = [
                (CGPoint(x: rect.minX,          y: rect.minY + length), CGPoint(x: rect.minX, y: rect.minY),          CGPoint(x: rect.minX + length, y: rect.minY)),
                (CGPoint(x: rect.maxX - length, y: rect.minY),          CGPoint(x: rect.maxX, y: rect.minY),          CGPoint(x: rect.maxX,          y: rect.minY + length)),
                (CGPoint(x: rect.minX,          y: rect.maxY - length), CGPoint(x: rect.minX, y: rect.maxY),          CGPoint(x: rect.minX + length, y: rect.maxY)),
                (CGPoint(x: rect.maxX - length, y: rect.maxY),          CGPoint(x: rect.maxX, y: rect.maxY),          CGPoint(x: rect.maxX,          y: rect.maxY - length)),
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
