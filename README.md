# PatchGuard

Road-surface capture system. Mobile apps sample camera frames at a configurable rate, tag each frame with GPS metadata, and batch-upload JPEGs to an ingest server.

## Components

| Component | Path | Description |
|-----------|------|-------------|
| iOS app | `PatchGuard/` | SwiftUI app (iOS 26.0+) |
| Android app | `patchguard-android/` | Jetpack Compose app (Android 8.0+ / API 26+) |
| Mock server | `server/` | Local Express.js server for development |

---

## Requirements

| Component | Requirements |
|-----------|-------------|
| iOS app | Xcode 26+, macOS, physical iPhone or iPad, Apple Developer account for signing |
| Android app | Android Studio (Ladybug or newer), physical device or emulator with camera |
| Mock server | Node.js 18+ |

Both mobile apps require a physical device for GPS tagging. The Android app can use an emulator for basic UI testing but GPS data will not be available.

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

### Android — `patchguard-android/app/src/main/res/values/config.xml`

| Key | Default | Description |
|-----|---------|-------------|
| `server_base_url` | `http://192.168.0.28:8000` | Base URL of the production backend |
| `mock_server_base_url` | `http://192.168.0.21:3000` | Base URL of the local mock server — update to your machine's LAN IP |
| `test_mode` | `true` | When `true`, targets `mock_server_base_url` and skips authentication |
| `batch_size` | `10` | Number of frames accumulated before a POST is triggered |

`network_security_config.xml` permits cleartext HTTP traffic for local development. Remove this for production builds.

---

## Operating Modes

### Production mode (`TEST_MODE = false` / `test_mode = false`)

- Targets `SERVER_BASE_URL` / `server_base_url`
- Shows a login screen on first launch; credentials are stored securely (iOS Keychain / Android EncryptedSharedPreferences) and reused on subsequent launches
- Each batch POST includes a `Bearer` token obtained from `POST /api/v1/auth/login`
- After a successful batch upload, fires `POST /api/v1/analysis/trigger` to kick off server-side processing
- Expects HTTP 201 from the batch endpoint

### Test mode (`TEST_MODE = true` / `test_mode = true`)

- Targets `MOCK_SERVER_BASE_URL` / `mock_server_base_url`
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
2. Set `TEST_MODE` / `test_mode` to `true` in the app config
3. Update `MOCK_SERVER_BASE_URL` / `mock_server_base_url` to `http://<your-ip>:3000`
4. Connect your device to the same Wi-Fi network as your machine

---

## iOS App

Open the project in Xcode:

```
PatchGuard/PatchGuard.xcodeproj
```

Build and run on a connected device from Xcode. Select your device as the run destination, choose a valid signing team in the project settings, then press Run.

---

## Android App

Open the `patchguard-android/` directory in Android Studio. Sync the Gradle project, then build and run on a connected device or emulator.

To build from the command line:

```bash
cd patchguard-android
./gradlew assembleDebug          # debug APK
./gradlew installDebug           # build and install on connected device
```

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

1. Ensure `TEST_MODE = false` in the app config
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
