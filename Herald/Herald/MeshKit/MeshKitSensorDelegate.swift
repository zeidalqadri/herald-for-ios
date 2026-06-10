//
//  MeshKitSensorDelegate.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

/// Callback for MeshKit contact events.
public protocol MeshKitContactDelegate: AnyObject {
    func meshKit(didDetectContact contact: MeshKitContact)
}

/// Herald SensorDelegate that parses incoming MeshKit payloads into MeshKitContact objects.
/// Maintains an in-memory contact log. Supports both v1 (plaintext) and v2 (encrypted) payloads.
public class MeshKitSensorDelegate: SensorDelegate {
    private let payloadSupplier: MeshKitPayloadSupplier
    public weak var contactDelegate: MeshKitContactDelegate?
    private var contacts: [MeshKitContact] = []
    private let queue = DispatchQueue(label: "io.meshkit.contacts")

    public init(payloadSupplier: MeshKitPayloadSupplier) {
        self.payloadSupplier = payloadSupplier
    }

    // MARK:- SensorDelegate

    public func sensor(_ sensor: SensorType, didRead: PayloadData, fromTarget: TargetIdentifier) {
        handlePayload(didRead, rssi: nil)
    }

    public func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: PayloadData) {
        handlePayload(withPayload, rssi: didMeasure.value)
    }

    public func sensor(_ sensor: SensorType, didShare: [PayloadData], fromTarget: TargetIdentifier) {
        for payload in didShare {
            handlePayload(payload, rssi: nil)
        }
    }

    // MARK:- Contact log

    /// Thread-safe snapshot of all detected contacts.
    public var contactLog: [MeshKitContact] {
        queue.sync { contacts }
    }

    /// Number of contacts detected.
    public var contactCount: Int {
        queue.sync { contacts.count }
    }

    /// Remove all contacts from the log.
    public func clearContacts() {
        queue.sync { contacts.removeAll() }
    }

    // MARK:- Internal

    private func handlePayload(_ payload: PayloadData, rssi: Double?) {
        guard let nodeId = payloadSupplier.decryptNodeId(from: payload) else { return }
        // Skip self-detection
        guard nodeId != payloadSupplier.nodeId else { return }
        let timestamp = payloadSupplier.decryptTimestamp(from: payload) ?? Date()
        let contact = MeshKitContact(remoteNodeId: nodeId, rssi: rssi ?? 0.0, timestamp: timestamp)
        queue.sync { contacts.append(contact) }
        contactDelegate?.meshKit(didDetectContact: contact)
    }
}
