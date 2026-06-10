//
//  LinuxStubs.swift
//
//  Minimal type stubs for building MeshKit on Linux (where CoreBluetooth is unavailable).
//  On Apple platforms this file compiles to nothing.
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

#if !canImport(CoreBluetooth)

import Foundation

// MARK:- Core Herald types needed by MeshKit

public typealias PayloadTimestamp = Date
public typealias TargetIdentifier = String

public class Device: NSObject {
    public var identifier: TargetIdentifier
    var createdAt: Date
    var lastUpdatedAt: Date

    init(_ identifier: TargetIdentifier) {
        self.createdAt = Date()
        self.identifier = identifier
        self.lastUpdatedAt = createdAt
    }
}

// MARK:- PayloadData

public class PayloadData: Hashable, Equatable {
    public var data: Data
    public var shortName: String {
        guard data.count > 0 else { return "" }
        guard data.count > 3 else { return data.base64EncodedString() }
        return String(data.subdata(in: 3..<data.count).base64EncodedString().prefix(6))
    }

    public init(_ data: Data) { self.data = data }
    public init() { self.data = Data() }
    public init(repeating: UInt8, count: Int) { self.data = Data(repeating: repeating, count: count) }
    public init?(base64Encoded: String) {
        guard let d = Data(base64Encoded: base64Encoded) else { return nil }
        self.data = d
    }

    public var count: Int { data.count }
    public var hexEncodedString: String { data.map { String(format: "%02hhX", $0) }.joined() }
    public func base64EncodedString() -> String { data.base64EncodedString() }
    public func subdata(in range: Range<Data.Index>) -> Data { data.subdata(in: range) }

    public var hashValue: Int { data.hashValue }
    public func hash(into hasher: inout Hasher) { data.hash(into: &hasher) }
    public static func ==(lhs: PayloadData, rhs: PayloadData) -> Bool { lhs.data == rhs.data }

    public func append(_ other: PayloadData) { data.append(other.data) }
    public func append(_ other: Data) { data.append(other) }
    public func append(_ other: UInt8) { data.append(Data([other.bigEndian])) }
    public func append(_ other: UInt16) {
        data.append(UInt8(other & 0xFF).bigEndian)
        data.append(UInt8((other >> 8) & 0xFF).bigEndian)
    }
    public func append(_ other: UInt32) {
        data.append(UInt8(other & 0xFF).bigEndian)
        data.append(UInt8((other >> 8) & 0xFF).bigEndian)
        data.append(UInt8((other >> 16) & 0xFF).bigEndian)
        data.append(UInt8((other >> 24) & 0xFF).bigEndian)
    }
    public func append(_ other: UInt64) {
        var v = other
        for _ in 0..<8 { data.append(UInt8(v & 0xFF).bigEndian); v >>= 8 }
    }
    public func append(_ other: Int8) { data.append(Data([UInt8(bitPattern: other)])) }
    public func append(_ other: Int16) { append(UInt16(bitPattern: other)) }
    public func append(_ other: Int32) { append(UInt32(bitPattern: other)) }
    public func append(_ other: Int64) { append(UInt64(bitPattern: other)) }
    public func append(_ other: Float32) { append(other.bitPattern) }
}

public class LegacyPayloadData: PayloadData {}

// MARK:- PayloadDataSupplier

public protocol PayloadDataSupplier {
    func legacyPayload(_ timestamp: PayloadTimestamp, device: Device?) -> LegacyPayloadData?
    func payload(_ timestamp: PayloadTimestamp, device: Device?) -> PayloadData?
    func payload(_ data: Data) -> [PayloadData]
}

public extension PayloadDataSupplier {
    func legacyPayload(_ timestamp: PayloadTimestamp, device: Device?) -> LegacyPayloadData? { nil }
    func payload(_ data: Data) -> [PayloadData] {
        let fixedLengthPayload = payload(PayloadTimestamp(), device: nil)
        var payloads: [PayloadData] = []
        if let fixedLengthPayload = fixedLengthPayload {
            let payloadLength = fixedLengthPayload.count
            var indexStart = 0, indexEnd = payloadLength
            while indexEnd <= data.count {
                payloads.append(PayloadData(data.subdata(in: indexStart..<indexEnd)))
                indexStart += payloadLength
                indexEnd += payloadLength
            }
        }
        return payloads
    }
}

// MARK:- SensorDelegate

public enum SensorType: String {
    case BLE, BLMESH, MOBILITY, GPS, BEACON, ULTRASOUND, ACCELEROMETER, OTHER, ARRAY
}

public enum SensorState: String {
    case on, off, unavailable
}

public enum ProximityMeasurementUnit: String {
    case RSSI, RTT
}

public struct Proximity {
    public let unit: ProximityMeasurementUnit
    public let value: Double
    public init(unit: ProximityMeasurementUnit, value: Double) {
        self.unit = unit
        self.value = value
    }
}

public protocol SensorDelegate {
    func sensor(_ sensor: SensorType, didDetect: TargetIdentifier)
    func sensor(_ sensor: SensorType, didRead: PayloadData, fromTarget: TargetIdentifier)
    func sensor(_ sensor: SensorType, didShare: [PayloadData], fromTarget: TargetIdentifier)
    func sensor(_ sensor: SensorType, didReceive: Data, fromTarget: TargetIdentifier)
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier)
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: PayloadData)
    func sensor(_ sensor: SensorType, didUpdateState: SensorState)
}

public extension SensorDelegate {
    func sensor(_ sensor: SensorType, didDetect: TargetIdentifier) {}
    func sensor(_ sensor: SensorType, didRead: PayloadData, fromTarget: TargetIdentifier) {}
    func sensor(_ sensor: SensorType, didShare: [PayloadData], fromTarget: TargetIdentifier) {}
    func sensor(_ sensor: SensorType, didReceive: Data, fromTarget: TargetIdentifier) {}
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier) {}
    func sensor(_ sensor: SensorType, didMeasure: Proximity, fromTarget: TargetIdentifier, withPayload: PayloadData) {}
    func sensor(_ sensor: SensorType, didUpdateState: SensorState) {}
}

// MARK:- Data extension (hexEncodedString for use by PayloadData)

public extension Data {
    var hexEncodedString: String { map { String(format: "%02hhX", $0) }.joined() }

    mutating func append(_ value: UInt8) {
        append(Foundation.Data([value.bigEndian]))
    }
}

#endif
