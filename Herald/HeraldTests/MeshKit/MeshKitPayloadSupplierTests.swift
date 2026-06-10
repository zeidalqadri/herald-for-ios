//
//  MeshKitPayloadSupplierTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import Herald

class MeshKitPayloadSupplierTests: XCTestCase {

    // MARK:- V1 tests (plaintext)

    func testPayloadProduces21Bytes() {
        let supplier = MeshKitPayloadSupplier()
        let payload = supplier.payload(PayloadTimestamp(), device: nil)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload!.count, 21)
    }

    func testPayloadVersionByte() {
        let supplier = MeshKitPayloadSupplier()
        let payload = supplier.payload(PayloadTimestamp(), device: nil)!
        XCTAssertEqual(payload.data[0], MeshKitPayloadSupplier.versionV1)
    }

    func testRoundtripNodeId() {
        let nodeId = UUID()
        let supplierA = MeshKitPayloadSupplier(nodeId: nodeId)
        let payload = supplierA.payload(PayloadTimestamp(), device: nil)!

        let parsedNodeId = MeshKitPayloadSupplier.parseNodeId(from: payload)
        XCTAssertNotNil(parsedNodeId)
        XCTAssertEqual(parsedNodeId, nodeId)
    }

    func testRoundtripTimestamp() {
        let supplier = MeshKitPayloadSupplier()
        let knownDate = Date(timeIntervalSince1970: 1718000000)
        let payload = supplier.payload(knownDate, device: nil)!

        let parsedDate = MeshKitPayloadSupplier.parseTimestamp(from: payload)
        XCTAssertNotNil(parsedDate)
        XCTAssertEqual(parsedDate!.timeIntervalSince1970, knownDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testNodeIdConsistentAcrossCalls() {
        let supplier = MeshKitPayloadSupplier()
        let payload1 = supplier.payload(PayloadTimestamp(), device: nil)!
        let payload2 = supplier.payload(PayloadTimestamp(), device: nil)!

        let nodeId1 = MeshKitPayloadSupplier.parseNodeId(from: payload1)
        let nodeId2 = MeshKitPayloadSupplier.parseNodeId(from: payload2)
        XCTAssertEqual(nodeId1, nodeId2)
    }

    func testCrossSupplierRoundtrip() {
        let nodeIdA = UUID()
        let supplierA = MeshKitPayloadSupplier(nodeId: nodeIdA)
        let payload = supplierA.payload(PayloadTimestamp(), device: nil)!

        let extractedNodeId = MeshKitPayloadSupplier.parseNodeId(from: payload)
        XCTAssertEqual(extractedNodeId, nodeIdA)
    }

    func testPayloadSplitting() {
        let supplier = MeshKitPayloadSupplier()
        let p1 = supplier.payload(PayloadTimestamp(), device: nil)!
        let p2 = supplier.payload(PayloadTimestamp(), device: nil)!

        var combined = Data()
        combined.append(p1.data)
        combined.append(p2.data)

        let split = supplier.payload(combined)
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].count, 21)
        XCTAssertEqual(split[1].count, 21)
    }

    // MARK:- V2 tests (encrypted)

    private func testKey() -> Data {
        // Fixed 16-byte key for deterministic tests
        return Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                     0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
    }

    func testEncryptedPayloadProduces33Bytes() {
        let supplier = MeshKitPayloadSupplier(encryptionKey: testKey())
        let payload = supplier.payload(PayloadTimestamp(), device: nil)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload!.count, 33)
    }

    func testEncryptedPayloadVersionByte() {
        let supplier = MeshKitPayloadSupplier(encryptionKey: testKey())
        let payload = supplier.payload(PayloadTimestamp(), device: nil)!
        XCTAssertEqual(payload.data[0], MeshKitPayloadSupplier.versionV2)
    }

    func testEncryptedRoundtripNodeId() {
        let nodeId = UUID()
        let key = testKey()
        let supplier = MeshKitPayloadSupplier(nodeId: nodeId, encryptionKey: key)
        let payload = supplier.payload(PayloadTimestamp(), device: nil)!

        let parsedNodeId = supplier.decryptNodeId(from: payload)
        XCTAssertNotNil(parsedNodeId)
        XCTAssertEqual(parsedNodeId, nodeId)
    }

    func testEncryptedRoundtripTimestamp() {
        let key = testKey()
        let supplier = MeshKitPayloadSupplier(encryptionKey: key)
        let knownDate = Date(timeIntervalSince1970: 1718000000)
        let payload = supplier.payload(knownDate, device: nil)!

        let parsedDate = supplier.decryptTimestamp(from: payload)
        XCTAssertNotNil(parsedDate)
        XCTAssertEqual(parsedDate!.timeIntervalSince1970, knownDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testEncryptedNodeIdConsistentAcrossCalls() {
        let key = testKey()
        let supplier = MeshKitPayloadSupplier(encryptionKey: key)
        let payload1 = supplier.payload(PayloadTimestamp(), device: nil)!
        let payload2 = supplier.payload(PayloadTimestamp(), device: nil)!

        let nodeId1 = supplier.decryptNodeId(from: payload1)
        let nodeId2 = supplier.decryptNodeId(from: payload2)
        XCTAssertEqual(nodeId1, nodeId2)
    }

    func testEncryptedDifferentNonces() {
        let key = testKey()
        let supplier = MeshKitPayloadSupplier(encryptionKey: key)
        let payload1 = supplier.payload(PayloadTimestamp(), device: nil)!
        let payload2 = supplier.payload(PayloadTimestamp(), device: nil)!

        // Nonce bytes (1..12) should differ
        let nonce1 = payload1.data.subdata(in: 1..<13)
        let nonce2 = payload2.data.subdata(in: 1..<13)
        XCTAssertNotEqual(nonce1, nonce2)
    }

    func testEncryptedCrossSupplierRoundtrip() {
        let nodeId = UUID()
        let key = testKey()
        let supplierA = MeshKitPayloadSupplier(nodeId: nodeId, encryptionKey: key)
        let supplierB = MeshKitPayloadSupplier(encryptionKey: key) // different node, same key

        let payload = supplierA.payload(PayloadTimestamp(), device: nil)!
        let parsedNodeId = supplierB.decryptNodeId(from: payload)
        XCTAssertEqual(parsedNodeId, nodeId)
    }

    func testEncryptedPayloadSplitting() {
        let key = testKey()
        let supplier = MeshKitPayloadSupplier(encryptionKey: key)
        let p1 = supplier.payload(PayloadTimestamp(), device: nil)!
        let p2 = supplier.payload(PayloadTimestamp(), device: nil)!

        var combined = Data()
        combined.append(p1.data)
        combined.append(p2.data)

        let split = supplier.payload(combined)
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].count, 33)
        XCTAssertEqual(split[1].count, 33)
    }

    func testDecryptNodeIdHandlesV1Payload() {
        let nodeId = UUID()
        let key = testKey()
        let v1Supplier = MeshKitPayloadSupplier(nodeId: nodeId)
        let v2Supplier = MeshKitPayloadSupplier(encryptionKey: key)

        let v1Payload = v1Supplier.payload(PayloadTimestamp(), device: nil)!
        // v2 supplier can still parse v1 payloads
        let parsedNodeId = v2Supplier.decryptNodeId(from: v1Payload)
        XCTAssertEqual(parsedNodeId, nodeId)
    }

    func testWrongKeyCannotDecrypt() {
        let nodeId = UUID()
        let key1 = testKey()
        let key2 = Data([0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
                         0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F])
        let supplierA = MeshKitPayloadSupplier(nodeId: nodeId, encryptionKey: key1)
        let supplierB = MeshKitPayloadSupplier(encryptionKey: key2)

        let payload = supplierA.payload(PayloadTimestamp(), device: nil)!
        let parsedNodeId = supplierB.decryptNodeId(from: payload)
        // Decrypts to garbage UUID, not the original
        XCTAssertNotEqual(parsedNodeId, nodeId)
    }
}
