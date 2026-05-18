//
//  FrameBuffer.swift
//  PatchGuard
//

import Foundation

@MainActor
final class FrameBuffer {
    struct Frame: Sendable {
        let jpeg: Data
        let metadata: ImageMetadata
    }

    let batchSize: Int
    private var buffer: [Frame] = []

    init() {
        batchSize = Bundle.main.object(forInfoDictionaryKey: "BATCH_SIZE") as? Int ?? 10
    }

    func add(jpeg: Data, metadata: ImageMetadata) {
        buffer.append(Frame(jpeg: jpeg, metadata: metadata))
        if buffer.count >= batchSize {
            flush()
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        Task.detached(priority: .utility) {
            IngestService.send(batch: batch)
        }
    }

    func clear() {
        buffer.removeAll()
    }
}
