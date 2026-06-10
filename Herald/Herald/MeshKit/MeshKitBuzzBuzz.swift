//
//  MeshKitBuzzBuzz.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// High-level facade that wires MeshKit for BuzzBuzz job relay.
///
/// Usage:
/// ```swift
/// let buzzbuzz = MeshKitBuzzBuzz(endpointURL: URL(string: "https://buzzbuzz.example.com/api/meshkit/envelopes")!)
/// buzzbuzz.start()
/// // When provider accepts a job offline:
/// buzzbuzz.acceptJob(jobRequestId: "jr-123", providerId: 456)
/// // Envelope is queued. When internet returns, it flushes automatically.
/// ```
public final class MeshKitBuzzBuzz {

    /// BuzzBuzz application identifier: ASCII "BB".
    public static let appId: UInt16 = 0x4242

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

    /// Queue a job acceptance envelope.
    /// The envelope is stored in the queue and flushed when internet is available.
    @discardableResult
    public func acceptJob(jobRequestId: String, providerId: Int) -> MeshKitEnvelope? {
        let payload: [String: Any] = [
            "type": "job_accept",
            "job_request_id": jobRequestId,
            "provider_id": providerId
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

    /// Queue a booking completion envelope.
    /// The envelope is stored in the queue and flushed when internet is available.
    @discardableResult
    public func completeBooking(bookingId: String, providerId: Int) -> MeshKitEnvelope? {
        let payload: [String: Any] = [
            "type": "booking_complete",
            "booking_id": bookingId,
            "provider_id": providerId
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
