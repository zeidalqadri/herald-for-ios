//
//  MeshKitPayloadSupplier.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
import CommonCrypto

/// MeshKit payload data supplier. Bridges Herald BLE transport with MeshKit identity.
///
/// V1 payload: [version:1][node_id:16][timestamp:4] = 21 bytes (plaintext)
/// V2 payload: [version:1][nonce:12][ciphertext:16][timestamp:4] = 33 bytes (AES-128-CTR encrypted)
///
/// Encryption uses AES-128 in CTR mode (the encryption step of AES-GCM without the auth tag).
/// The 12-byte nonce is random per payload; IV = nonce || 0x00000000.
public class MeshKitPayloadSupplier: PayloadDataSupplier {
    public static let payloadLengthV1: Int = 21
    public static let payloadLengthV2: Int = 33
    public static let versionV1: UInt8 = 1
    public static let versionV2: UInt8 = 2

    // Legacy constants for backward compatibility with v1-only code
    public static let payloadLength: Int = payloadLengthV1
    public static let version: UInt8 = versionV1

    /// This node's 128-bit identifier, stable across calls.
    public let nodeId: UUID

    /// 16-byte AES-128 encryption key. nil = unencrypted (v1).
    private let encryptionKey: Data?

    /// Current payload length based on encryption mode.
    public var currentPayloadLength: Int {
        encryptionKey != nil ? Self.payloadLengthV2 : Self.payloadLengthV1
    }

    /// Current version based on encryption mode.
    public var currentVersion: UInt8 {
        encryptionKey != nil ? Self.versionV2 : Self.versionV1
    }

    public init(nodeId: UUID = UUID(), encryptionKey: Data? = nil) {
        if let key = encryptionKey {
            precondition(key.count == 16, "Encryption key must be 16 bytes")
        }
        self.nodeId = nodeId
        self.encryptionKey = encryptionKey
    }

    // MARK:- PayloadDataSupplier

    public func legacyPayload(_ timestamp: PayloadTimestamp, device: Device?) -> LegacyPayloadData? {
        return nil
    }

    public func payload(_ timestamp: PayloadTimestamp, device: Device?) -> PayloadData? {
        if let key = encryptionKey {
            return encryptedPayload(timestamp, key: key)
        }
        return unencryptedPayload(timestamp)
    }

    public func payload(_ data: Data) -> [PayloadData] {
        let length = currentPayloadLength
        var payloads: [PayloadData] = []
        var indexStart = 0, indexEnd = length
        while indexEnd <= data.count {
            let payload = PayloadData(data.subdata(in: indexStart..<indexEnd))
            payloads.append(payload)
            indexStart += length
            indexEnd += length
        }
        return payloads
    }

    // MARK:- V1 Payload (plaintext)

    private func unencryptedPayload(_ timestamp: PayloadTimestamp) -> PayloadData {
        let payloadData = PayloadData()
        payloadData.append(Self.versionV1)
        payloadData.append(withUnsafeBytes(of: nodeId.uuid) { Data($0) })
        let seconds = max(0, timestamp.timeIntervalSince1970)
        let epoch = UInt32(clamping: Int64(seconds))
        payloadData.append(epoch)
        return payloadData
    }

    // MARK:- V2 Payload (encrypted)

    private func encryptedPayload(_ timestamp: PayloadTimestamp, key: Data) -> PayloadData? {
        var nonce = Data(count: 12)
        let result = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!)
        }
        guard result == errSecSuccess else { return nil }

        let plaintext = withUnsafeBytes(of: nodeId.uuid) { Data($0) }
        guard let ciphertext = Self.aesCTRCrypt(data: plaintext, key: key, nonce: nonce) else { return nil }

        let payloadData = PayloadData()
        payloadData.append(Self.versionV2)
        payloadData.append(nonce)
        payloadData.append(ciphertext)
        let seconds = max(0, timestamp.timeIntervalSince1970)
        let epoch = UInt32(clamping: Int64(seconds))
        payloadData.append(epoch)
        return payloadData
    }

    // MARK:- Parsing (static, v1 only)

    /// Extract node ID from a v1 (plaintext) MeshKit payload.
    public static func parseNodeId(from payload: PayloadData) -> UUID? {
        guard payload.count == payloadLengthV1 else { return nil }
        guard payload.data[0] == versionV1 else { return nil }
        let uuidBytes = payload.data.subdata(in: 1..<17)
        return uuidBytes.withUnsafeBytes { ptr -> UUID? in
            guard ptr.count == 16 else { return nil }
            return UUID(uuid: ptr.load(as: uuid_t.self))
        }
    }

    /// Extract timestamp from a v1 (plaintext) MeshKit payload.
    public static func parseTimestamp(from payload: PayloadData) -> Date? {
        guard payload.count == payloadLengthV1 else { return nil }
        let tsData = payload.data.subdata(in: 17..<21)
        let ts: UInt32 = tsData.withUnsafeBytes { $0.load(as: UInt32.self) }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    // MARK:- Parsing (instance, v1 + v2)

    /// Extract node ID from any MeshKit payload version. Uses encryption key for v2.
    public func decryptNodeId(from payload: PayloadData) -> UUID? {
        guard payload.count > 0 else { return nil }
        let ver = payload.data[0]

        if ver == Self.versionV1 {
            return Self.parseNodeId(from: payload)
        } else if ver == Self.versionV2 {
            guard payload.count == Self.payloadLengthV2 else { return nil }
            guard let key = encryptionKey else { return nil }
            let nonce = payload.data.subdata(in: 1..<13)
            let ciphertext = payload.data.subdata(in: 13..<29)
            guard let plaintext = Self.aesCTRCrypt(data: ciphertext, key: key, nonce: nonce) else { return nil }
            return plaintext.withUnsafeBytes { ptr -> UUID? in
                guard ptr.count == 16 else { return nil }
                return UUID(uuid: ptr.load(as: uuid_t.self))
            }
        }
        return nil
    }

    /// Extract timestamp from any MeshKit payload version.
    public func decryptTimestamp(from payload: PayloadData) -> Date? {
        guard payload.count > 0 else { return nil }
        let ver = payload.data[0]

        if ver == Self.versionV1 {
            return Self.parseTimestamp(from: payload)
        } else if ver == Self.versionV2 {
            guard payload.count == Self.payloadLengthV2 else { return nil }
            let tsData = payload.data.subdata(in: 29..<33)
            let ts: UInt32 = tsData.withUnsafeBytes { $0.load(as: UInt32.self) }
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }
        return nil
    }

    // MARK:- AES-128-CTR

    /// AES-128 CTR encrypt/decrypt (symmetric operation). IV = nonce(12) || 0x00000000(4).
    static func aesCTRCrypt(data input: Data, key: Data, nonce: Data) -> Data? {
        guard key.count == 16, nonce.count == 12 else { return nil }
        let ivBytes = [UInt8](nonce) + [UInt8](repeating: 0, count: 4)
        let keyBytes = [UInt8](key)
        let inputBytes = [UInt8](input)
        var output = [UInt8](repeating: 0, count: input.count)
        var outputLen: size_t = 0

        var cryptorRef: CCCryptorRef?
        var status = CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeCTR),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            ivBytes, keyBytes, keyBytes.count,
            nil, 0, 0,
            CCModeOptions(kCCModeOptionCTR_BE),
            &cryptorRef
        )
        guard status == kCCSuccess, let ref = cryptorRef else { return nil }
        status = CCCryptorUpdate(ref, inputBytes, inputBytes.count, &output, output.count, &outputLen)
        CCCryptorRelease(ref)
        guard status == kCCSuccess else { return nil }
        return Data(output.prefix(outputLen))
    }
}
