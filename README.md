# PatchGuard

Road-surface capture system. An iOS app samples camera frames at a configurable rate, tags each frame with GPS metadata, and batch-uploads JPEGs to a local ingest server over LAN.

## Components

| Component | Path | Description |
|-----------|------|-------------|
| iOS app | `PatchGuard/` | SwiftUI app (iOS 26.0+) |
| Ingest server | `server/` | Express.js receiver |

---

## Requirements

- **iOS app**: Xcode 26+, physical iPhone or iPad (camera + GPS required), Apple Developer account for signing
- **Server**: Node.js 18+

---

## Configuration

App configuration lives in `PatchGuard/PatchGuard/Info.plist`.

| Key | Default | Description |
|-----|---------|-------------|
| `SERVER_ENDPOINT` | `http://172.20.10.4:3000/api/v1/images/batch` | Full URL of the batch upload endpoint. Must be reachable from the device over LAN. |
| `BATCH_SIZE` | `10` | Number of frames accumulated before a POST is triggered. |

**To point the app at your machine:**

1. Find your Mac's LAN IP address: `ipconfig getifaddr en0`
2. Open `PatchGuard/PatchGuard/Info.plist` in Xcode (or any text editor)
3. Update `SERVER_ENDPOINT` to `http://<your-mac-ip>:3000/api/v1/images/batch`

The app uses `NSAllowsArbitraryLoads` so plain HTTP to local addresses works without additional ATS configuration.

---

## Running the Server

```bash
cd server
npm install
npm start
```

The server binds to `0.0.0.0:3000` and is reachable from any device on the same network.

```
GET  http://<mac-ip>:3000/health                  # health check
POST http://<mac-ip>:3000/api/v1/images/batch     # batch ingest
```

Uploaded JPEGs are saved to `server/uploads/`. Each batch is logged to stdout with GPS coordinates, altitude, heading, and accuracy.

---

## Running the iOS App

```bash
open PatchGuard/PatchGuard.xcodeproj
```

Build and run on a connected device from Xcode. CLI build (requires valid signing identity):

```bash
xcodebuild -project PatchGuard/PatchGuard.xcodeproj \
           -scheme PatchGuard \
           -destination 'generic/platform=iOS' \
           build
```

---

## Basic Usage

1. Start the server on your Mac (`npm start` in `server/`)
2. Connect your iPhone to the same Wi-Fi network as your Mac
3. Update `SERVER_ENDPOINT` in `Info.plist` with your Mac's LAN IP
4. Build and run the app on your device
5. Grant camera and location permissions when prompted
6. Select a capture rate (1, 2, or 5 FPS) and tap **Start**
7. Point the camera at the road surface while moving
8. Frames are buffered and uploaded in batches of `BATCH_SIZE`; progress appears in the server log and in `server/uploads/`
9. Tap **Stop** to end the session

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
