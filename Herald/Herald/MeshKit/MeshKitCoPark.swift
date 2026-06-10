//
//  MeshKitCoPark.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// High-level facade that wires MeshKit for CoPark bay confirmations.
///
/// Usage:
/// ```swift
/// let copark = MeshKitCoPark(endpointURL: URL(string: "https://copark.example.com/api/meshkit/envelopes")!)
/// copark.start()
/// // When user confirms parking in basement:
/// copark.confirmBay(bookingId: "abc-123", userId: "user-456")
/// // Envelope is queued. When internet returns, it flushes automatically.
/// ```
public final class MeshKitCoPark {

    /// CoPark application identifier: ASCII "CP".
    public static let appId: UInt16 = 0x4350

    public let identity: MeshKitIdentity
    public let nodeId: UUID
    public let queue: MeshKitQueue
    public let surface: MeshKitSurface
    public let payloadSupplier: MeshKitPayloadSupplier
    public let sensorDelegate: MeshKitSensorDelegate

    #if canImport(Network)
    public let surfaceMonitor: MeshKitSurfaceMonitor
    #endif

    /// Create with an existing identity seed (32 bytes) or generate a new one.
    public init(endpointURL: URL, identitySeed: Data? = nil, httpClient: MeshKitHTTPClient? = nil) {
        if let seed = identitySeed {
            self.identity = try! MeshKitIdentity(seed: seed)
        } else {
            self.identity = MeshKitIdentity()
        }
        self.nodeId = UUID()
        self.queue = MeshKitQueue()
        self.surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: httpClient)
        self.payloadSupplier = MeshKitPayloadSupplier(nodeId: nodeId)
        self.sensorDelegate = MeshKitSensorDelegate(payloadSupplier: payloadSupplier)
        self.sensorDelegate.queue = queue

        #if canImport(Network)
        self.surfaceMonitor = MeshKitSurfaceMonitor(queue: queue)
        #endif
    }

    /// Start BLE scanning + surface monitoring.
    public func start() {
        #if canImport(Network)
        surfaceMonitor.start()
        #endif
    }

    /// Stop everything.
    public func stop() {
        #if canImport(Network)
        surfaceMonitor.stop()
        #endif
    }

    /// Queue a bay confirmation envelope.
    /// The envelope is stored in the queue and flushed when internet is available.
    @discardableResult
    public func confirmBay(bookingId: String, userId: String) -> MeshKitEnvelope? {
        let payload: [String: Any] = [
            "type": "bay_confirm",
            "booking_id": bookingId,
            "user_id": userId,
            "timestamp": Int(Date().timeIntervalSince1970)
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        guard let envelope = try? MeshKitEnvelope.sealBroadcast(
            payload: jsonData,
            appId: Self.appId,
            fromNodeId: nodeId,
            identity: identity,
            ttl: 10
        ) else {
            return nil
        }
        queue.enqueue(envelope)
        surface.flush()
        return envelope
    }

    deinit { stop() }
}
