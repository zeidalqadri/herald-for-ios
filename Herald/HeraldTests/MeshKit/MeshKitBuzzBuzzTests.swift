//
//  MeshKitBuzzBuzzTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

// MARK:- Test doubles

private class BuzzBuzzMockHTTPClient: MeshKitHTTPClient {
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

class MeshKitBuzzBuzzTests: XCTestCase {

    private let endpointURL = URL(string: "https://buzzbuzz.test/api/meshkit/envelopes")!

    private func makeBuzzBuzz(http: BuzzBuzzMockHTTPClient = BuzzBuzzMockHTTPClient()) -> MeshKitBuzzBuzz {
        MeshKitBuzzBuzz(endpointURL: endpointURL, httpClient: http)
    }

    // 1. appId constant is ASCII "BB"
    func testAppId() {
        XCTAssertEqual(MeshKitBuzzBuzz.appId, 0x4242)
    }

    // 2. acceptJob returns a non-nil envelope
    func testAcceptJobCreatesEnvelope() {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = buzzbuzz.acceptJob(jobRequestId: "jr-001", providerId: 123)
        XCTAssertNotNil(envelope)
    }

    // 3. acceptJob payload type == "job_accept"
    func testAcceptJobPayloadType() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.acceptJob(jobRequestId: "jr-type", providerId: 123))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "job_accept")
    }

    // 4. acceptJob payload contains job_request_id
    func testAcceptJobPayloadContainsJobRequestId() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.acceptJob(jobRequestId: "jr-abc", providerId: 123))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["job_request_id"] as? String, "jr-abc")
    }

    // 5. acceptJob payload contains provider_id
    func testAcceptJobPayloadContainsProviderId() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.acceptJob(jobRequestId: "jr-abc", providerId: 456))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["provider_id"] as? Int, 456)
    }

    // 6. completeBooking returns a non-nil envelope
    func testCompleteBookingCreatesEnvelope() {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = buzzbuzz.completeBooking(bookingId: "bk-001", providerId: 123)
        XCTAssertNotNil(envelope)
    }

    // 7. completeBooking payload type == "booking_complete"
    func testCompleteBookingPayloadType() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.completeBooking(bookingId: "bk-type", providerId: 123))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "booking_complete")
    }

    // 8. completeBooking payload contains booking_id
    func testCompleteBookingPayloadContainsBookingId() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.completeBooking(bookingId: "bk-xyz", providerId: 123))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["booking_id"] as? String, "bk-xyz")
    }

    // 9. completeBooking payload contains provider_id
    func testCompleteBookingPayloadContainsProviderId() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.completeBooking(bookingId: "bk-xyz", providerId: 789))
        let payloadData = try envelope.openBroadcast()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        XCTAssertEqual(json["provider_id"] as? Int, 789)
    }

    // 10. Envelope appId matches BuzzBuzz appId
    func testAppIdInEnvelope() throws {
        let buzzbuzz = makeBuzzBuzz()
        let envelope = try XCTUnwrap(buzzbuzz.acceptJob(jobRequestId: "jr-appid", providerId: 123))
        XCTAssertEqual(envelope.appId, MeshKitBuzzBuzz.appId)
    }
}
