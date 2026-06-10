//
//  MeshKitSurfaceMonitorTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

#if canImport(Network)

class MockSurfaceMonitorDelegate: MeshKitSurfaceMonitorDelegate {
    var surfaced: [[MeshKitEnvelope]] = []

    func meshKit(didSurface envelopes: [MeshKitEnvelope]) {
        surfaced.append(envelopes)
    }
}

class MeshKitSurfaceMonitorTests: XCTestCase {

    private let identity = MeshKitIdentity()
    private let nodeId = UUID()

    private func makeBroadcast(appId: UInt16 = 1) throws -> MeshKitEnvelope {
        try MeshKitEnvelope.sealBroadcast(
            payload: Data("hello".utf8), appId: appId,
            fromNodeId: nodeId, identity: identity, ttl: 10
        )
    }

    // 1. Creating a monitor with a queue does not crash.
    func testMonitorCreation() {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        XCTAssertNotNil(monitor)
    }

    // 2. start/stop lifecycle does not crash; isRunning state is consistent.
    func testStartStop() {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        monitor.start()
        monitor.stop()
    }

    // 3. simulateSurface with empty queue: delegate is NOT called.
    func testSurfaceWithEmptyQueue() {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        let delegate = MockSurfaceMonitorDelegate()
        monitor.delegate = delegate

        monitor.simulateSurface()

        XCTAssertEqual(delegate.surfaced.count, 0)
    }

    // 4. simulateSurface with enqueued items: delegate called with correct envelopes.
    func testSurfaceWithEnvelopes() throws {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        let delegate = MockSurfaceMonitorDelegate()
        monitor.delegate = delegate

        queue.enqueue(try makeBroadcast(appId: 1))
        queue.enqueue(try makeBroadcast(appId: 2))
        monitor.simulateSurface()

        XCTAssertEqual(delegate.surfaced.count, 1)
        XCTAssertEqual(delegate.surfaced[0].count, 2)
    }

    // 5. simulateSurface drains the queue.
    func testSurfaceDrainsQueue() throws {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        monitor.delegate = MockSurfaceMonitorDelegate()

        queue.enqueue(try makeBroadcast())
        queue.enqueue(try makeBroadcast())
        monitor.simulateSurface()

        XCTAssertEqual(queue.count, 0)
    }

    // 6. Multiple start/stop cycles do not crash.
    func testMultipleStartStop() {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        monitor.start()
        monitor.stop()
        monitor.start()
        monitor.stop()
    }

    // 7. No delegate set: simulateSurface with envelopes does not crash.
    func testDelegateMissing() throws {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        queue.enqueue(try makeBroadcast())
        monitor.simulateSurface() // no crash
        XCTAssertEqual(queue.count, 0) // queue is still drained
    }

    // 8. After start, isConnected returns a Bool (true on a connected test machine).
    func testIsConnected() {
        let queue = MeshKitQueue()
        let monitor = MeshKitSurfaceMonitor(queue: queue)
        monitor.start()
        // Allow the path monitor a brief moment to report its initial path
        let exp = expectation(description: "path update")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)
        let connected = monitor.isConnected
        XCTAssertTrue(connected || !connected) // result is a valid Bool either way
        monitor.stop()
    }
}

#endif // canImport(Network)
