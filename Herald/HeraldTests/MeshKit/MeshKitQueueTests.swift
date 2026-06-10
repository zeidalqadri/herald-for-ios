//
//  MeshKitQueueTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

class MockDeliveryDelegate: MeshKitDeliveryDelegate {
    var deliveries: [(envelopes: [MeshKitEnvelope], peer: UUID)] = []

    func meshKit(shouldDeliver envelopes: [MeshKitEnvelope], toPeer nodeId: UUID) {
        deliveries.append((envelopes, nodeId))
    }
}

class MeshKitQueueTests: XCTestCase {

    private let identity = MeshKitIdentity()
    private let nodeId = UUID()

    private func broadcast(appId: UInt16 = 1, ttl: UInt8 = 10) throws -> MeshKitEnvelope {
        try MeshKitEnvelope.sealBroadcast(
            payload: Data("hello".utf8), appId: appId,
            fromNodeId: nodeId, identity: identity, ttl: ttl
        )
    }

    private func directed(to recipientId: UUID, recipientIdentity: MeshKitIdentity) throws -> MeshKitEnvelope {
        try MeshKitEnvelope.sealDirected(
            payload: Data("dm".utf8), appId: 1, fromNodeId: nodeId,
            identity: identity, toNodeId: recipientId,
            recipientAgreementPublicKey: recipientIdentity.agreementPublicKey
        )
    }

    // MARK:- Basic operations

    func testEnqueueAndCount() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast())
        XCTAssertEqual(queue.count, 1)
        XCTAssertFalse(queue.isEmpty)
    }

    func testCapacityDropsOldest() throws {
        let queue = MeshKitQueue(capacity: 3)
        let env1 = try broadcast(appId: 1)
        let env2 = try broadcast(appId: 2)
        let env3 = try broadcast(appId: 3)
        let env4 = try broadcast(appId: 4)
        queue.enqueue(env1); queue.enqueue(env2); queue.enqueue(env3); queue.enqueue(env4)
        // Capacity 3: oldest (env1) should be dropped
        XCTAssertEqual(queue.count, 3)
        let all = queue.drain()
        XCTAssertFalse(all.contains { $0.appId == 1 }) // env1 dropped
    }

    func testTTLEviction() throws {
        let queue = MeshKitQueue(ttl: 0.05)
        queue.enqueue(try broadcast())
        XCTAssertEqual(queue.count, 1)
        Thread.sleep(forTimeInterval: 0.12)
        XCTAssertEqual(queue.count, 0)
        XCTAssertTrue(queue.isEmpty)
    }

    // MARK:- dequeueForPeer

    func testDequeueForPeerBroadcast() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast())
        let got = queue.dequeueForPeer(UUID()) // any peer
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(queue.count, 0) // removed from queue
    }

    func testDequeueForPeerBroadcastAtMaxHops() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast(ttl: 0)) // hops=0 == ttl=0, not relayable
        XCTAssertEqual(queue.dequeueForPeer(UUID()).count, 0)
    }

    func testDequeueForPeerDirectedExactMatch() throws {
        let recipientId = UUID()
        let recipientIdentity = MeshKitIdentity()
        let queue = MeshKitQueue()
        queue.enqueue(try directed(to: recipientId, recipientIdentity: recipientIdentity))
        XCTAssertEqual(queue.dequeueForPeer(recipientId).count, 1)
    }

    func testDequeueForPeerDirectedWrongPeer() throws {
        let recipientId = UUID()
        let recipientIdentity = MeshKitIdentity()
        let queue = MeshKitQueue()
        queue.enqueue(try directed(to: recipientId, recipientIdentity: recipientIdentity))
        XCTAssertEqual(queue.dequeueForPeer(UUID()).count, 0) // different peer
        XCTAssertEqual(queue.count, 1) // still there
    }

    // MARK:- peekForPeer

    func testPeekDoesNotRemove() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast())
        let peeked = queue.peekForPeer(UUID())
        XCTAssertEqual(peeked.count, 1)
        XCTAssertEqual(queue.count, 1) // not removed
    }

    // MARK:- dequeueBroadcasts

    func testDequeueBroadcastsLeavesDirected() throws {
        let recipientId = UUID()
        let recipientIdentity = MeshKitIdentity()
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast(appId: 1))
        queue.enqueue(try broadcast(appId: 2))
        queue.enqueue(try directed(to: recipientId, recipientIdentity: recipientIdentity))
        let broadcasts = queue.dequeueBroadcasts()
        XCTAssertEqual(broadcasts.count, 2)
        XCTAssertEqual(queue.count, 1) // directed remains
    }

    // MARK:- remove / drain / clear

    func testRemovePredicate() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast(appId: 1))
        queue.enqueue(try broadcast(appId: 2))
        let removed = queue.remove { $0.appId == 1 }
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(queue.count, 1)
    }

    func testDrain() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast(appId: 1))
        queue.enqueue(try broadcast(appId: 2))
        let all = queue.drain()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(queue.count, 0)
    }

    func testClear() throws {
        let queue = MeshKitQueue()
        queue.enqueue(try broadcast()); queue.enqueue(try broadcast())
        queue.clear()
        XCTAssertEqual(queue.count, 0)
    }

    // MARK:- SensorDelegate integration

    func testSensorDelegateTriggersDeliveryCallback() throws {
        let peerSupplier = MeshKitPayloadSupplier()
        let localSupplier = MeshKitPayloadSupplier()
        let sensorDelegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)
        let queue = MeshKitQueue()
        let deliveryMock = MockDeliveryDelegate()
        sensorDelegate.queue = queue
        sensorDelegate.deliveryDelegate = deliveryMock

        // Enqueue a broadcast envelope
        queue.enqueue(try broadcast())

        // Simulate detecting the peer
        let payload = peerSupplier.payload(PayloadTimestamp(), device: nil)!
        sensorDelegate.sensor(.BLE, didRead: payload, fromTarget: "peer1")

        // Delivery callback should have fired
        XCTAssertEqual(deliveryMock.deliveries.count, 1)
        XCTAssertEqual(deliveryMock.deliveries[0].envelopes.count, 1)
        XCTAssertEqual(deliveryMock.deliveries[0].peer, peerSupplier.nodeId)
    }

    func testSensorDelegateNoCallbackWhenQueueEmpty() throws {
        let peerSupplier = MeshKitPayloadSupplier()
        let localSupplier = MeshKitPayloadSupplier()
        let sensorDelegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)
        let queue = MeshKitQueue()
        let deliveryMock = MockDeliveryDelegate()
        sensorDelegate.queue = queue
        sensorDelegate.deliveryDelegate = deliveryMock

        let payload = peerSupplier.payload(PayloadTimestamp(), device: nil)!
        sensorDelegate.sensor(.BLE, didRead: payload, fromTarget: "peer1")

        XCTAssertEqual(deliveryMock.deliveries.count, 0)
    }
}
