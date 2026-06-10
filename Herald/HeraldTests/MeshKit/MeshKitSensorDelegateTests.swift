//
//  MeshKitSensorDelegateTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
@testable import Herald

class MockContactDelegate: MeshKitContactDelegate {
    var receivedContacts: [MeshKitContact] = []

    func meshKit(didDetectContact contact: MeshKitContact) {
        receivedContacts.append(contact)
    }
}

class MeshKitSensorDelegateTests: XCTestCase {

    private func testKey() -> Data {
        return Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
                     0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F])
    }

    // MARK:- V1 (plaintext) delegate tests

    func testDidReadCreatesContact() {
        let remoteNodeId = UUID()
        let remoteSupplier = MeshKitPayloadSupplier(nodeId: remoteNodeId)
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let payload = remoteSupplier.payload(PayloadTimestamp(), device: nil)!
        delegate.sensor(.BLE, didRead: payload, fromTarget: "target1")

        XCTAssertEqual(delegate.contactCount, 1)
        XCTAssertEqual(delegate.contactLog[0].remoteNodeId, remoteNodeId)
    }

    func testDidMeasureWithPayloadCreatesContactWithRSSI() {
        let remoteNodeId = UUID()
        let remoteSupplier = MeshKitPayloadSupplier(nodeId: remoteNodeId)
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let payload = remoteSupplier.payload(PayloadTimestamp(), device: nil)!
        let proximity = Proximity(unit: .RSSI, value: -65.0)
        delegate.sensor(.BLE, didMeasure: proximity, fromTarget: "target1", withPayload: payload)

        XCTAssertEqual(delegate.contactCount, 1)
        XCTAssertEqual(delegate.contactLog[0].remoteNodeId, remoteNodeId)
        XCTAssertEqual(delegate.contactLog[0].rssi, -65.0, accuracy: 0.01)
    }

    func testInvalidPayloadIgnored() {
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let badPayload = PayloadData(Data([0xFF, 0x01, 0x02]))
        delegate.sensor(.BLE, didRead: badPayload, fromTarget: "target1")

        XCTAssertEqual(delegate.contactCount, 0)
    }

    func testSelfDetectionIgnored() {
        let supplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: supplier)

        // Supplier receives its own payload
        let payload = supplier.payload(PayloadTimestamp(), device: nil)!
        delegate.sensor(.BLE, didRead: payload, fromTarget: "self")

        XCTAssertEqual(delegate.contactCount, 0)
    }

    func testContactLogGrows() {
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        for _ in 0..<5 {
            let remote = MeshKitPayloadSupplier()
            let payload = remote.payload(PayloadTimestamp(), device: nil)!
            delegate.sensor(.BLE, didRead: payload, fromTarget: "target")
        }

        XCTAssertEqual(delegate.contactCount, 5)
    }

    func testContactDelegateCallbackFires() {
        let remoteSupplier = MeshKitPayloadSupplier()
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)
        let mock = MockContactDelegate()
        delegate.contactDelegate = mock

        let payload = remoteSupplier.payload(PayloadTimestamp(), device: nil)!
        delegate.sensor(.BLE, didRead: payload, fromTarget: "target1")

        XCTAssertEqual(mock.receivedContacts.count, 1)
        XCTAssertEqual(mock.receivedContacts[0].remoteNodeId, remoteSupplier.nodeId)
    }

    func testClearContacts() {
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let remote = MeshKitPayloadSupplier()
        let payload = remote.payload(PayloadTimestamp(), device: nil)!
        delegate.sensor(.BLE, didRead: payload, fromTarget: "target")

        XCTAssertEqual(delegate.contactCount, 1)
        delegate.clearContacts()
        XCTAssertEqual(delegate.contactCount, 0)
    }

    // MARK:- V2 (encrypted) delegate tests

    func testEncryptedDidReadCreatesContact() {
        let key = testKey()
        let remoteNodeId = UUID()
        let remoteSupplier = MeshKitPayloadSupplier(nodeId: remoteNodeId, encryptionKey: key)
        let localSupplier = MeshKitPayloadSupplier(encryptionKey: key)
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let payload = remoteSupplier.payload(PayloadTimestamp(), device: nil)!
        delegate.sensor(.BLE, didRead: payload, fromTarget: "target1")

        XCTAssertEqual(delegate.contactCount, 1)
        XCTAssertEqual(delegate.contactLog[0].remoteNodeId, remoteNodeId)
    }

    func testDidShareCreatesMultipleContacts() {
        let localSupplier = MeshKitPayloadSupplier()
        let delegate = MeshKitSensorDelegate(payloadSupplier: localSupplier)

        let remote1 = MeshKitPayloadSupplier()
        let remote2 = MeshKitPayloadSupplier()
        let payload1 = remote1.payload(PayloadTimestamp(), device: nil)!
        let payload2 = remote2.payload(PayloadTimestamp(), device: nil)!

        delegate.sensor(.BLE, didShare: [payload1, payload2], fromTarget: "relay")

        XCTAssertEqual(delegate.contactCount, 2)
    }
}
