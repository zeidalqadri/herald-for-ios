//
//  MeshKitCoParkTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

// MARK:- Test doubles

private class CoParkMockHTTPClient: MeshKitHTTPClient {
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

// MARK:- Tests

class MeshKitCoParkTests: XCTestCase {

    private let endpointURL = URL(string: "https://copark.test/api/meshkit/envelopes")!

    private func makeCoPark(http: CoParkMockHTTPClient = CoParkMockHTTPClient()) -> MeshKitCoPark {
        MeshKitCoPark(endpointURL: endpointURL, httpClient: http)
    }

    // 1. appId constant is ASCII "CP"
    func testAppId() {
        XCTAssertEqual(MeshKitCoPark.appId, 0x4350)
    }

    // 2. confirmBay returns a non-nil envelope
    func testConfirmBayCreatesEnvelope() {
        let copark = makeCoPark()
        let envelope = copark.confirmBay(bookingId: "bk-001", userId: "u-001")
        XCTAssertNotNil(envelope)
    }

    // 3. After confirmBay, at least one envelope was enqueued.
    //    Verified by using a non-200 HTTP client so the envelope is re-enqueued after the flush attempt.
    func testConfirmBayEnqueues() {
        let http = CoParkMockHTTPClient()
        http.statusCode = 503
        let copark = MeshKitCoPark(endpointURL: endpointURL, httpClient: http)
        copark.confirmBay(bookingId: "bk-enq", userId: "u-enq")

        let exp = expectation(description: "re-enqueued")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        // 503 causes MeshKitSurface to re-enqueue, so queue has 1 item
        XCTAssertEqual(copark.queue.count, 1)
    }

    // 4. Payload JSON contains booking_id
    func testConfirmBayPayloadContainsBookingId() throws {
        let copark = makeCoPark()
        let envelope = try XCTUnwrap(copark.confirmBay(bookingId: "booking-abc", userId: "user-xyz"))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["booking_id"] as? String, "booking-abc")
    }

    // 5. Payload JSON contains user_id
    func testConfirmBayPayloadContainsUserId() throws {
        let copark = makeCoPark()
        let envelope = try XCTUnwrap(copark.confirmBay(bookingId: "booking-abc", userId: "user-xyz"))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["user_id"] as? String, "user-xyz")
    }

    // 6. Payload JSON type == "bay_confirm"
    func testConfirmBayPayloadContainsType() throws {
        let copark = makeCoPark()
        let envelope = try XCTUnwrap(copark.confirmBay(bookingId: "b1", userId: "u1"))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "bay_confirm")
    }

    // 7. Envelope appId matches CoPark appId
    func testConfirmBayAppIdInEnvelope() throws {
        let copark = makeCoPark()
        let envelope = try XCTUnwrap(copark.confirmBay(bookingId: "b1", userId: "u1"))
        XCTAssertEqual(envelope.appId, MeshKitCoPark.appId)
    }

    // 8. After confirm + flush with 200 response, queue drains to 0
    func testConfirmBayFlushesQueue() throws {
        let http = CoParkMockHTTPClient()
        let copark = MeshKitCoPark(endpointURL: endpointURL, httpClient: http)
        copark.confirmBay(bookingId: "b-flush", userId: "u-flush")

        let exp = expectation(description: "flush delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(copark.queue.count, 0)
        XCTAssertEqual(http.requests.count, 1)
    }

    // 9. Three confirmations are all delivered via mock HTTP
    func testMultipleConfirmations() throws {
        let http = CoParkMockHTTPClient()
        let copark = MeshKitCoPark(endpointURL: endpointURL, httpClient: http)
        copark.confirmBay(bookingId: "b1", userId: "u1")
        copark.confirmBay(bookingId: "b2", userId: "u2")
        copark.confirmBay(bookingId: "b3", userId: "u3")

        let exp = expectation(description: "all delivered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(http.requests.count, 3)
        XCTAssertEqual(copark.queue.count, 0)
    }
}
