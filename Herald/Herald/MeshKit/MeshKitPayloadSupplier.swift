//
//  MeshKitPayloadSupplier.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// MeshKit payload data supplier. Bridges Herald BLE transport with MeshKit identity.
/// Payload format: [version:1][node_id:16][timestamp:4] = 21 bytes.
/// No encryption in this phase — placeholder for Phase 2.
public class MeshKitPayloadSupplier: PayloadDataSupplier {
    public static let payloadLength: Int = 21
    public static let version: UInt8 = 1

    /// This node's 128-bit identifier, stable across calls.
    public let nodeId: UUID

    public init(nodeId: UUID = UUID()) {
        self.nodeId = nodeId
    }

    // MARK:- PayloadDataSupplier

    public func legacyPayload(_ timestamp: PayloadTimestamp, device: Device?) -> LegacyPayloadData? {
        return nil
    }

    public func payload(_ timestamp: PayloadTimestamp, device: Device?) -> PayloadData? {
        let payloadData = PayloadData()
        // [version:1]
        payloadData.append(MeshKitPayloadSupplier.version)
        // [node_id:16] — RFC 4122 byte order
        payloadData.append(withUnsafeBytes(of: nodeId.uuid) { Data($0) })
        // [timestamp:4] — UInt32 seconds since Unix epoch, little-endian
        let seconds = max(0, timestamp.timeIntervalSince1970)
        let epoch = UInt32(clamping: Int64(seconds))
        payloadData.append(epoch)
        return payloadData
    }

    public func payload(_ data: Data) -> [PayloadData] {
        var payloads: [PayloadData] = []
        var indexStart = 0, indexEnd = MeshKitPayloadSupplier.payloadLength
        while indexEnd <= data.count {
            let payload = PayloadData(data.subdata(in: indexStart..<indexEnd))
            payloads.append(payload)
            indexStart += MeshKitPayloadSupplier.payloadLength
            indexEnd += MeshKitPayloadSupplier.payloadLength
        }
        return payloads
    }

    // MARK:- Parsing

    /// Extract node ID from a MeshKit payload.
    public static func parseNodeId(from payload: PayloadData) -> UUID? {
        guard payload.count == payloadLength else { return nil }
        guard payload.data[0] == version else { return nil }
        let uuidBytes = payload.data.subdata(in: 1..<17)
        return uuidBytes.withUnsafeBytes { ptr -> UUID? in
            guard ptr.count == 16 else { return nil }
            return UUID(uuid: ptr.load(as: uuid_t.self))
        }
    }

    /// Extract timestamp from a MeshKit payload.
    public static func parseTimestamp(from payload: PayloadData) -> Date? {
        guard payload.count == payloadLength else { return nil }
        let tsData = payload.data.subdata(in: 17..<21)
        let ts: UInt32 = tsData.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }
}
