//
//  MeshKitEnvelopeTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import MeshKit

class MeshKitEnvelopeTests: XCTestCase {

    private let testPayload = Data("hello meshkit".utf8)

    // MARK:- Broadcast

    func testBroadcastSealAndOpen() throws {
        let identity = MeshKitIdentity()
        let nodeId = UUID()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 1, fromNodeId: nodeId, identity: identity
        )
        let opened = try envelope.openBroadcast()
        XCTAssertEqual(opened, testPayload)
    }

    func testBroadcastSignatureVerification() throws {
        let identity = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 1, fromNodeId: UUID(), identity: identity
        )
        XCTAssertTrue(try envelope.verifySignature())
    }

    func testBroadcastTamperedPayload() throws {
        let identity = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 1, fromNodeId: UUID(), identity: identity
        )
        var bytes = envelope.serialize()
        // Tamper with a payload byte (located after the fixed header)
        // Broadcast header: version(1)+flags(1)+appId(2)+fromNodeId(16)+fromPubKey(32)+ts(4)+ttl(1)+hops(1)+payloadLen(2) = 60
        bytes[60] ^= 0xFF
        let tampered = try MeshKitEnvelope.deserialize(bytes)
        XCTAssertFalse(try tampered.verifySignature())
    }

    func testBroadcastSerializeDeserialize() throws {
        let identity = MeshKitIdentity()
        let nodeId = UUID()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 42, fromNodeId: nodeId, identity: identity, ttl: 7
        )
        let bytes = envelope.serialize()
        let restored = try MeshKitEnvelope.deserialize(bytes)

        XCTAssertEqual(restored.flags, 0x00)
        XCTAssertEqual(restored.appId, 42)
        XCTAssertEqual(restored.fromNodeId, nodeId)
        XCTAssertEqual(restored.fromSigningPublicKey, identity.signingPublicKey)
        XCTAssertNil(restored.toNodeId)
        XCTAssertNil(restored.ephemeralPublicKey)
        XCTAssertEqual(restored.timestamp, envelope.timestamp)
        XCTAssertEqual(restored.ttl, 7)
        XCTAssertEqual(restored.hops, 0)
        XCTAssertEqual(restored.payload, testPayload)
        XCTAssertNil(restored.nonce)
        XCTAssertNil(restored.tag)
        XCTAssertEqual(restored.signature, envelope.signature)

        // Signature should still verify after round-trip
        XCTAssertTrue(try restored.verifySignature())
        let opened = try restored.openBroadcast()
        XCTAssertEqual(opened, testPayload)
    }

    // MARK:- Directed

    func testDirectedSealAndOpen() throws {
        let sender = MeshKitIdentity()
        let recipient = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealDirected(
            payload: testPayload,
            appId: 2,
            fromNodeId: UUID(),
            identity: sender,
            toNodeId: UUID(),
            recipientAgreementPublicKey: recipient.agreementPublicKey
        )
        let opened = try envelope.openDirected(identity: recipient)
        XCTAssertEqual(opened, testPayload)
    }

    func testDirectedWrongRecipient() throws {
        let sender = MeshKitIdentity()
        let recipient = MeshKitIdentity()
        let attacker = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealDirected(
            payload: testPayload,
            appId: 2,
            fromNodeId: UUID(),
            identity: sender,
            toNodeId: UUID(),
            recipientAgreementPublicKey: recipient.agreementPublicKey
        )
        XCTAssertThrowsError(try envelope.openDirected(identity: attacker))
    }

    func testDirectedSignatureVerification() throws {
        let sender = MeshKitIdentity()
        let recipient = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealDirected(
            payload: testPayload,
            appId: 2,
            fromNodeId: UUID(),
            identity: sender,
            toNodeId: UUID(),
            recipientAgreementPublicKey: recipient.agreementPublicKey
        )
        XCTAssertTrue(try envelope.verifySignature())
    }

    func testDirectedSerializeDeserialize() throws {
        let sender = MeshKitIdentity()
        let recipient = MeshKitIdentity()
        let fromId = UUID()
        let toId = UUID()
        let envelope = try MeshKitEnvelope.sealDirected(
            payload: testPayload,
            appId: 99,
            fromNodeId: fromId,
            identity: sender,
            toNodeId: toId,
            recipientAgreementPublicKey: recipient.agreementPublicKey
        )
        let bytes = envelope.serialize()
        let restored = try MeshKitEnvelope.deserialize(bytes)

        XCTAssertEqual(restored.flags, 0x03)
        XCTAssertEqual(restored.appId, 99)
        XCTAssertEqual(restored.fromNodeId, fromId)
        XCTAssertEqual(restored.fromSigningPublicKey, sender.signingPublicKey)
        XCTAssertEqual(restored.toNodeId, toId)
        XCTAssertEqual(restored.ephemeralPublicKey, envelope.ephemeralPublicKey)
        XCTAssertEqual(restored.timestamp, envelope.timestamp)
        XCTAssertEqual(restored.hops, 0)
        XCTAssertEqual(restored.nonce, envelope.nonce)
        XCTAssertEqual(restored.payload, envelope.payload)
        XCTAssertEqual(restored.tag, envelope.tag)
        XCTAssertEqual(restored.signature, envelope.signature)

        // Signature should still verify
        XCTAssertTrue(try restored.verifySignature())
        // Should still decrypt
        let opened = try restored.openDirected(identity: recipient)
        XCTAssertEqual(opened, testPayload)
    }

    // MARK:- Relay

    func testRelay() throws {
        let identity = MeshKitIdentity()
        var envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 1, fromNodeId: UUID(), identity: identity, ttl: 3
        )
        XCTAssertEqual(envelope.hops, 0)

        XCTAssertTrue(envelope.relay())
        XCTAssertEqual(envelope.hops, 1)

        XCTAssertTrue(envelope.relay())
        XCTAssertEqual(envelope.hops, 2)

        XCTAssertTrue(envelope.relay())
        XCTAssertEqual(envelope.hops, 3)

        // hops(3) >= ttl(3), should return false
        XCTAssertFalse(envelope.relay())
        XCTAssertEqual(envelope.hops, 3)
    }

    // MARK:- Payload limits

    func testMaxPayloadSize() throws {
        let identity = MeshKitIdentity()
        let oversized = Data(repeating: 0xAB, count: MeshKitEnvelope.maxPayloadSize + 1)
        XCTAssertThrowsError(try MeshKitEnvelope.sealBroadcast(
            payload: oversized, appId: 1, fromNodeId: UUID(), identity: identity
        ))
    }

    // MARK:- Field preservation

    func testTimestampPreserved() throws {
        let identity = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 1, fromNodeId: UUID(), identity: identity
        )
        let bytes = envelope.serialize()
        let restored = try MeshKitEnvelope.deserialize(bytes)
        XCTAssertEqual(restored.timestamp, envelope.timestamp)
    }

    func testAppIdPreserved() throws {
        let identity = MeshKitIdentity()
        let envelope = try MeshKitEnvelope.sealBroadcast(
            payload: testPayload, appId: 0x1234, fromNodeId: UUID(), identity: identity
        )
        let bytes = envelope.serialize()
        let restored = try MeshKitEnvelope.deserialize(bytes)
        XCTAssertEqual(restored.appId, 0x1234)
    }
}
