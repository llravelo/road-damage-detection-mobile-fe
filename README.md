# PatchGuard

## Introduction

PatchGuard is a road damage survey and assessment system. It helps field teams and road authorities locate, document, and evaluate damage such as potholes, cracks, and surface deterioration by combining mobile image capture with server-side analysis.

This repository contains the **mobile survey app** — the data-collection front end of that system. The app lets users survey roads by capturing camera frames as they travel, automatically tagging each frame with GPS location, heading, and altitude. Captured frames are batched and forwarded to the inference server, where they are analyzed to detect and assess road damage.

The iOS app samples camera frames at a configurable rate, tags each frame with GPS metadata, and batch-uploads JPEGs to an ingest server.

## Components

| Component | Path | Description |
|-----------|------|-------------|
| iOS app | `PatchGuard/` | SwiftUI app (iOS 26.0+) |
| Mock server | `server/` | Local Express.js server for development |

---

## Requirements

| Component | Requirements |
|-----------|-------------|
| iOS app | Xcode 26+, macOS, physical iPhone or iPad, Apple Developer account for signing |
| Mock server | Node.js 18+ |

The iOS app requires a physical device for camera and GPS tagging.

---

## Configuration

### iOS — `PatchGuard/PatchGuard/Info.plist`

| Key | Default | Description |
|-----|---------|-------------|
| `SERVER_BASE_URL` | `https://api-patchguard.ngrok.dev` | Base URL of the production backend |
| `MOCK_SERVER_BASE_URL` | `http://192.168.0.21:3000` | Base URL of the local mock server — update to your machine's LAN IP |
| `TEST_MODE` | `false` | When `true`, targets `MOCK_SERVER_BASE_URL` and skips authentication |
| `BATCH_SIZE` | `10` | Number of frames accumulated before a POST is triggered |

`NSAllowsArbitraryLoads` is enabled so plain HTTP to local addresses works without extra ATS configuration.

---

## Operating Modes

### Production mode (`TEST_MODE = false`)

- Targets `SERVER_BASE_URL`
- Shows a login screen on first launch; credentials are stored securely in the iOS Keychain and reused on subsequent launches
- Each batch POST includes a `Bearer` token obtained from `POST /api/v1/auth/login`
- After a successful batch upload, fires `POST /api/v1/analysis/trigger` to kick off server-side processing
- Expects HTTP 201 from the batch endpoint

### Test mode (`TEST_MODE = true`)

- Targets `MOCK_SERVER_BASE_URL`
- Login screen is bypassed entirely — no authentication
- Batch POST sends no `Authorization` header
- Expects HTTP 200 from the batch endpoint
- Use with the local Express server in `server/`

---

## Mock Server

### Setup

```bash
cd server
npm install
npm start
```

The server binds to `0.0.0.0:3000` and is reachable from any device on the same network.

### Endpoints

```
GET  http://<your-ip>:3000/health                  # health check
POST http://<your-ip>:3000/api/v1/images/batch     # batch ingest (returns 200)
```

Uploaded JPEGs are saved to `server/uploads/`. Each batch is logged to stdout with GPS coordinates, altitude, heading, and accuracy.

### Pointing the app at the mock server

1. Find your machine's LAN IP address (check your network settings or run `hostname -I` on Linux / `ipconfig` on Windows)
2. Set `TEST_MODE` to `true` in `Info.plist`
3. Update `MOCK_SERVER_BASE_URL` to `http://<your-ip>:3000`
4. Connect your device to the same Wi-Fi network as your machine

---

## iOS App

Open the project in Xcode:

```
PatchGuard/PatchGuard.xcodeproj
```

Build and run on a connected device from Xcode. Select your device as the run destination, choose a valid signing team in the project settings, then press Run.

---

## Basic Usage

### Against the mock server

1. Configure `TEST_MODE = true` and set `MOCK_SERVER_BASE_URL` to `http://<your-ip>:3000`
2. Start the mock server: `cd server && npm start`
3. Build and run the app on a device connected to the same Wi-Fi
4. The app goes straight to the capture screen — no login required
5. Select a capture rate (1, 2, or 5 FPS) and tap **Start**
6. Batches upload automatically; check `server/uploads/` for saved frames and stdout for metadata logs

### Against production

1. Ensure `TEST_MODE = false` in `Info.plist`
2. Build and run the app
3. Enter your credentials on the login screen; they are saved securely for future launches
4. Select a capture rate and tap **Start**

---

## Wire Format

`POST /api/v1/images/batch` — `multipart/form-data`

| Part | Type | Description |
|------|------|-------------|
| `files[]` | binary | JPEG image parts, one per frame |
| `items_json` | string | JSON array of metadata objects |

Each metadata object:

```json
{
  "filename": "frame_001.jpg",
  "latitude": 37.7749,
  "longitude": -122.4194,
  "captured_at": "2026-05-18T10:30:00Z",
  "heading": 270.0,
  "altitude": 15.3,
  "gps_accuracy": 4.1
}
```

`heading`, `altitude`, and `gps_accuracy` are optional.

The production endpoint returns HTTP 201 on success. The mock server returns HTTP 200.
