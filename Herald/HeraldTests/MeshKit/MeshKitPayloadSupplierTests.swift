//
//  MeshKitPayloadSupplierTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import Herald

class MeshKitPayloadSupplierTests: XCTestCase {

    func testPayloadProduces21Bytes() {
        let supplier = MeshKitPayloadSupplier()
        let payload = supplier.payload(PayloadTimestamp(), device: nil)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload!.count, 21)
    }

    func testPayloadVersionByte() {
        let supplier = MeshKitPayloadSupplier()
        let payload = supplier.payload(PayloadTimestamp(), device: nil)!
        XCTAssertEqual(payload.data[0], MeshKitPayloadSupplier.version)
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
}
