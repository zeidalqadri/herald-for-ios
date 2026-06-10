//
//  MeshKitQueue.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Called when a detected peer has pending envelopes in the queue.
public protocol MeshKitDeliveryDelegate: AnyObject {
    /// Deliver these envelopes to the peer. The implementor handles GATT writes.
    func meshKit(shouldDeliver envelopes: [MeshKitEnvelope], toPeer nodeId: UUID)
}

/// Bounded, thread-safe in-memory store-and-forward queue for MeshKitEnvelope.
public final class MeshKitQueue {

    public static let defaultCapacity = 200
    public static let defaultTTL: TimeInterval = 24 * 60 * 60

    private struct Entry {
        let envelope: MeshKitEnvelope
        let enqueuedAt: Date
    }

    private var storage: [Entry] = []
    private let serialQueue = DispatchQueue(label: "io.meshkit.queue")
    private let capacity: Int
    private let ttl: TimeInterval

    public init(capacity: Int = defaultCapacity, ttl: TimeInterval = defaultTTL) {
        self.capacity = capacity
        self.ttl = ttl
    }

    // MARK:- Public API

    @discardableResult
    public func enqueue(_ envelope: MeshKitEnvelope) -> Bool {
        serialQueue.sync {
            evictExpired()
            if storage.count >= capacity {
                storage.removeFirst()
            }
            storage.append(Entry(envelope: envelope, enqueuedAt: Date()))
        }
        return true
    }

    public func dequeueForPeer(_ nodeId: UUID) -> [MeshKitEnvelope] {
        serialQueue.sync {
            evictExpired()
            let matched = storage.filter { matchesPeer($0.envelope, nodeId: nodeId) }
            storage.removeAll { matchesPeer($0.envelope, nodeId: nodeId) }
            return matched.map { $0.envelope }
        }
    }

    public func peekForPeer(_ nodeId: UUID) -> [MeshKitEnvelope] {
        serialQueue.sync {
            evictExpired()
            return storage
                .filter { matchesPeer($0.envelope, nodeId: nodeId) }
                .map { $0.envelope }
        }
    }

    public func dequeueBroadcasts() -> [MeshKitEnvelope] {
        serialQueue.sync {
            evictExpired()
            let matched = storage.filter { isBroadcastRelayable($0.envelope) }
            storage.removeAll { isBroadcastRelayable($0.envelope) }
            return matched.map { $0.envelope }
        }
    }

    @discardableResult
    public func remove(where predicate: @escaping (MeshKitEnvelope) -> Bool) -> Int {
        serialQueue.sync {
            evictExpired()
            let before = storage.count
            storage.removeAll { predicate($0.envelope) }
            return before - storage.count
        }
    }

    public var count: Int {
        serialQueue.sync {
            evictExpired()
            return storage.count
        }
    }

    public var isEmpty: Bool {
        serialQueue.sync {
            evictExpired()
            return storage.isEmpty
        }
    }

    public func clear() {
        serialQueue.sync { storage.removeAll() }
    }

    public func drain() -> [MeshKitEnvelope] {
        serialQueue.sync {
            evictExpired()
            let all = storage.map { $0.envelope }
            storage.removeAll()
            return all
        }
    }

    // MARK:- Private helpers (must be called inside serialQueue)

    private func evictExpired() {
        let cutoff = Date().addingTimeInterval(-ttl)
        storage.removeAll { $0.enqueuedAt < cutoff }
    }

    private func matchesPeer(_ envelope: MeshKitEnvelope, nodeId: UUID) -> Bool {
        if let to = envelope.toNodeId {
            return to == nodeId
        }
        return isBroadcastRelayable(envelope)
    }

    private func isBroadcastRelayable(_ envelope: MeshKitEnvelope) -> Bool {
        envelope.toNodeId == nil && envelope.hops < envelope.ttl
    }
}
