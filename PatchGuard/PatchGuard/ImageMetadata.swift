//
//  ImageMetadata.swift
//  PatchGuard
//

import Foundation

struct ImageMetadata: Encodable, Sendable {
    let filename: String
    let latitude: Double
    let longitude: Double
    let captured_at: String
    let heading: Double?
    let altitude: Double?
    let gps_accuracy: Double?
}
