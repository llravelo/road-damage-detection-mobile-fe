//
//  IngestService.swift
//  PatchGuard
//

import Foundation

enum IngestService {
    static let isTestMode: Bool =
        Bundle.main.object(forInfoDictionaryKey: "TEST_MODE") as? Bool ?? false

    private static let baseURL: URL = {
        let key = isTestMode ? "MOCK_SERVER_BASE_URL" : "SERVER_BASE_URL"
        let fallback = isTestMode ? "http://localhost:3000" : "http://192.168.0.21:8000"
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? fallback
        return URL(string: raw)!
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    // Hardcoded test credentials — seeded in backend on startup
    private static let testEmail = "test@example.com"
    private static let testPassword = "testpassword123"

    private static var accessToken: String?

    private static func ensureToken() async throws {
        guard accessToken == nil else { return }
        let url = baseURL.appendingPathComponent("api/v1/auth/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(testEmail)&password=\(testPassword)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("[Ingest] Login failed: HTTP \(code)")
            throw URLError(.badServerResponse)
        }
        struct TokenResponse: Decodable { let access_token: String }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = decoded.access_token
    }

    static func send(batch: [FrameBuffer.Frame]) async {
        guard !batch.isEmpty else { return }
        if !isTestMode {
            do { try await ensureToken() } catch {
                print("[Ingest] Auth failed: \(error.localizedDescription)")
                return
            }
        }

        let boundary = "PGBoundary-\(UUID().uuidString)"
        var body = Data()

        for frame in batch {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"files\"; filename=\"\(frame.metadata.filename)\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(frame.jpeg)
            body.appendString("\r\n")
        }

        if let itemsJSON = try? JSONEncoder().encode(batch.map(\.metadata)) {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"items_json\"\r\n\r\n")
            body.append(itemsJSON)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")

        let url = baseURL.appendingPathComponent("api/v1/images/batch")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !isTestMode, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if !isTestMode && http.statusCode == 401 { accessToken = nil }  // expired — reset so next call re-auths
                let expectedOK = isTestMode ? 200 : 201
                if http.statusCode != expectedOK { print("[Ingest] HTTP \(http.statusCode)"); return }
            }
        } catch {
            print("[Ingest] \(error.localizedDescription)")
            return
        }

        if !isTestMode {
            // TODO: remove once the server handles analysis on a periodic schedule (e.g. Celery Beat)
            var triggerRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/analysis/trigger"))
            triggerRequest.httpMethod = "POST"
            if let token = accessToken {
                triggerRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            _ = try? await session.data(for: triggerRequest)
        }
    }

}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
