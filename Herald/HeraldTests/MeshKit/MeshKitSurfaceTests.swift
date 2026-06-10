//
//  MeshKitSurfaceTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

// MARK:- Test doubles

class MockHTTPClient: MeshKitHTTPClient {
    var statusCode: Int = 200
    var error: Error? = nil
    var requests: [(url: URL, body: Data)] = []

    func post(url: URL, body: Data, completion: @escaping (Result<Int, Error>) -> Void) {
        requests.append((url, body))
        if let error = error {
            completion(.failure(error))
        } else {
            completion(.success(statusCode))
        }
    }
}

class MockSurfaceDelegate: MeshKitSurfaceDelegate {
    var delivered: [MeshKitEnvelope] = []
    var failed: [(envelope: MeshKitEnvelope, error: Error)] = []

    func meshKitSurface(didDeliver envelope: MeshKitEnvelope) {
        delivered.append(envelope)
    }
    func meshKitSurface(didFailDelivery envelope: MeshKitEnvelope, error: Error) {
        failed.append((envelope, error))
    }
}

// MARK:- Tests

class MeshKitSurfaceTests: XCTestCase {

    private let identity = MeshKitIdentity()
    private let nodeId = UUID()
    private let endpointURL = URL(string: "https://relay.test/meshkit/envelopes")!

    private func makeBroadcast(appId: UInt16 = 1) throws -> MeshKitEnvelope {
        try MeshKitEnvelope.sealBroadcast(
            payload: Data("test".utf8), appId: appId,
            fromNodeId: nodeId, identity: identity, ttl: 10
        )
    }

    // Flush delivers all queued envelopes
    func testFlushDeliversAll() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)
        let delegate = MockSurfaceDelegate()
        surface.delegate = delegate

        queue.enqueue(try makeBroadcast(appId: 1))
        queue.enqueue(try makeBroadcast(appId: 2))
        surface.flush()

        // Wait for async delivery
        let exp = expectation(description: "delivery")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(http.requests.count, 2)
        XCTAssertEqual(delegate.delivered.count, 2)
        XCTAssertEqual(delegate.failed.count, 0)
    }

    // Flush on empty queue is a no-op
    func testFlushEmptyQueueNoOp() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)

        surface.flush()

        let exp = expectation(description: "noop")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(http.requests.count, 0)
    }

    // HTTP error re-enqueues envelope
    func testHTTPErrorReenqueues() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        http.statusCode = 503
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)
        let delegate = MockSurfaceDelegate()
        surface.delegate = delegate

        queue.enqueue(try makeBroadcast())
        surface.flush()

        let exp = expectation(description: "fail")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(queue.count, 1) // re-enqueued
    }

    // Network error re-enqueues envelope
    func testNetworkErrorReenqueues() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        http.error = URLError(.notConnectedToInternet)
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)
        let delegate = MockSurfaceDelegate()
        surface.delegate = delegate

        queue.enqueue(try makeBroadcast())
        surface.flush()

        let exp = expectation(description: "net error")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(delegate.failed.count, 1)
        XCTAssertEqual(queue.count, 1)
    }

    // POSTs serialized envelope bytes to the correct URL
    func testPostURLAndBody() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)

        let env = try makeBroadcast()
        queue.enqueue(env)
        surface.flush()

        let exp = expectation(description: "post")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(http.requests.first?.url, endpointURL)
        XCTAssertEqual(http.requests.first?.body, env.serialize())
    }

    // After successful flush, queue is empty
    func testQueueEmptyAfterSuccessfulFlush() throws {
        let queue = MeshKitQueue()
        let http = MockHTTPClient()
        let surface = MeshKitSurface(queue: queue, endpointURL: endpointURL, httpClient: http)

        queue.enqueue(try makeBroadcast(appId: 1))
        queue.enqueue(try makeBroadcast(appId: 2))
        surface.flush()

        let exp = expectation(description: "empty")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(queue.count, 0)
    }
}
