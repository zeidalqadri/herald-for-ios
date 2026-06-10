//
//  MeshKitContact.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Record of a detected MeshKit peer.
public struct MeshKitContact: Codable {
    public let remoteNodeId: UUID
    public let rssi: Double
    public let timestamp: Date

    public init(remoteNodeId: UUID, rssi: Double, timestamp: Date = Date()) {
        self.remoteNodeId = remoteNodeId
        self.rssi = rssi
        self.timestamp = timestamp
    }
}
