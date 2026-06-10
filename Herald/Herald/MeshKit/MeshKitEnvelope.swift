//
//  MeshKitEnvelope.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Binary store-and-forward envelope with two modes:
///
/// **Broadcast** (flags=0x00): signed plaintext
/// ```
/// [version:1][flags:1][app_id:2 LE][from_node_id:16][from_pubkey:32]
/// [ts:4 LE][ttl:1][hops:1][payload_len:2 LE][payload:N][sig:64]
/// ```
///
/// **Directed encrypted** (flags=0x03): signed + encrypted
/// ```
/// [version:1][flags:1][app_id:2 LE][from_node_id:16][from_pubkey:32]
/// [to_node_id:16][ephemeral_pubkey:32][ts:4 LE][ttl:1][hops:1]
/// [payload_len:2 LE][nonce:12][ciphertext:N][tag:16][sig:64]
/// ```
///
/// Signature covers everything except hops and the trailing 64-byte signature.
/// Encryption: ECIES with ephemeral X25519 -> HKDF-SHA256 -> ChaCha20-Poly1305.
public struct MeshKitEnvelope {

    public static let version: UInt8 = 1
    public static let maxPayloadSize: Int = 400 // stay under 512 GATT

    // MARK:- Flags

    /// Bit 0: directed (toNodeId present). Bit 1: encrypted (ephemeral key + nonce + tag present).
    public static let flagDirected: UInt8 = 0x01
    public static let flagEncrypted: UInt8 = 0x02

    // MARK:- Fields

    public let flags: UInt8
    public let appId: UInt16
    public let fromNodeId: UUID
    public let fromSigningPublicKey: Data  // 32 bytes
    public let toNodeId: UUID?             // nil for broadcast
    public let ephemeralPublicKey: Data?   // 32 bytes, directed only
    public let timestamp: UInt32
    public let ttl: UInt8
    public private(set) var hops: UInt8
    public let nonce: Data?                // 12 bytes, encrypted only
    public let payload: Data               // cleartext (broadcast) or ciphertext (directed)
    public let tag: Data?                  // 16 bytes, encrypted only
    public let signature: Data             // 64 bytes

    // MARK:- Seal Broadcast

    /// Create a signed plaintext broadcast envelope.
    public static func sealBroadcast(
        payload: Data,
        appId: UInt16,
        fromNodeId: UUID,
        identity: MeshKitIdentity,
        ttl: UInt8 = 10
    ) throws -> MeshKitEnvelope {
        guard payload.count <= maxPayloadSize else { throw MeshKitCryptoError.payloadTooLarge }

        let ts = UInt32(max(0, Int64(Date().timeIntervalSince1970)))
        var envelope = MeshKitEnvelope(
            flags: 0x00,
            appId: appId,
            fromNodeId: fromNodeId,
            fromSigningPublicKey: identity.signingPublicKey,
            toNodeId: nil,
            ephemeralPublicKey: nil,
            timestamp: ts,
            ttl: ttl,
            hops: 0,
            nonce: nil,
            payload: payload,
            tag: nil,
            signature: Data(count: 64) // placeholder
        )

        let toSign = envelope.signableBytes()
        let sig = try identity.sign(toSign)
        envelope = MeshKitEnvelope(
            flags: envelope.flags,
            appId: envelope.appId,
            fromNodeId: envelope.fromNodeId,
            fromSigningPublicKey: envelope.fromSigningPublicKey,
            toNodeId: envelope.toNodeId,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            timestamp: envelope.timestamp,
            ttl: envelope.ttl,
            hops: envelope.hops,
            nonce: envelope.nonce,
            payload: envelope.payload,
            tag: envelope.tag,
            signature: sig
        )
        return envelope
    }

    // MARK:- Seal Directed

    /// Create a signed and encrypted directed envelope.
    public static func sealDirected(
        payload: Data,
        appId: UInt16,
        fromNodeId: UUID,
        identity: MeshKitIdentity,
        toNodeId: UUID,
        recipientAgreementPublicKey: Data
    ) throws -> MeshKitEnvelope {
        guard payload.count <= maxPayloadSize else { throw MeshKitCryptoError.payloadTooLarge }

        // 1. Generate ephemeral X25519 key pair
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPub = Data(ephemeralKey.publicKey.rawRepresentation)

        // 2. ECDH with recipient's static agreement key
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientAgreementPublicKey)
        let shared = try ephemeralKey.sharedSecretFromKeyAgreement(with: peerKey)

        // 3. Generate 12-byte random nonce
        var nonceBytes = Data(count: 12)
        #if canImport(CryptoKit)
        let status = nonceBytes.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 12, $0.baseAddress!)
        }
        if status != errSecSuccess {
            nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        }
        #else
        nonceBytes = Data((0..<12).map { _ in UInt8.random(in: 0...255) })
        #endif

        // 4. KDF
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: nonceBytes,
            sharedInfo: Data("meshkit-v1".utf8),
            outputByteCount: 32
        )

        // 5. ChaCha20-Poly1305 seal
        let chaChaNonce = try ChaChaPoly.Nonce(data: nonceBytes)
        let sealedBox = try ChaChaPoly.seal(payload, using: symmetricKey, nonce: chaChaNonce)
        let ciphertext = Data(sealedBox.ciphertext)
        let authTag = Data(sealedBox.tag)

        let ts = UInt32(max(0, Int64(Date().timeIntervalSince1970)))
        let flags: UInt8 = Self.flagDirected | Self.flagEncrypted

        var envelope = MeshKitEnvelope(
            flags: flags,
            appId: appId,
            fromNodeId: fromNodeId,
            fromSigningPublicKey: identity.signingPublicKey,
            toNodeId: toNodeId,
            ephemeralPublicKey: ephemeralPub,
            timestamp: ts,
            ttl: 10,
            hops: 0,
            nonce: nonceBytes,
            payload: ciphertext,
            tag: authTag,
            signature: Data(count: 64) // placeholder
        )

        let toSign = envelope.signableBytes()
        let sig = try identity.sign(toSign)
        envelope = MeshKitEnvelope(
            flags: envelope.flags,
            appId: envelope.appId,
            fromNodeId: envelope.fromNodeId,
            fromSigningPublicKey: envelope.fromSigningPublicKey,
            toNodeId: envelope.toNodeId,
            ephemeralPublicKey: envelope.ephemeralPublicKey,
            timestamp: envelope.timestamp,
            ttl: envelope.ttl,
            hops: envelope.hops,
            nonce: envelope.nonce,
            payload: envelope.payload,
            tag: envelope.tag,
            signature: sig
        )
        return envelope
    }

    // MARK:- Open

    /// Open a broadcast envelope: verify signature and return the plaintext payload.
    public func openBroadcast() throws -> Data {
        guard flags == 0x00 else { throw MeshKitCryptoError.invalidEnvelope }
        guard try verifySignature() else { throw MeshKitCryptoError.signatureVerificationFailed }
        return payload
    }

    /// Open a directed envelope: verify signature then decrypt payload.
    public func openDirected(identity: MeshKitIdentity) throws -> Data {
        guard flags == (Self.flagDirected | Self.flagEncrypted) else {
            throw MeshKitCryptoError.invalidEnvelope
        }
        guard try verifySignature() else { throw MeshKitCryptoError.signatureVerificationFailed }

        guard let ephemeralPub = ephemeralPublicKey,
              let nonceBytes = nonce,
              let authTag = tag else {
            throw MeshKitCryptoError.invalidEnvelope
        }

        // ECDH with sender's ephemeral key using our agreement key
        let shared = try identity.sharedSecret(with: ephemeralPub)
        let symmetricKey = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: nonceBytes,
            sharedInfo: Data("meshkit-v1".utf8),
            outputByteCount: 32
        )

        let chaChaNonce = try ChaChaPoly.Nonce(data: nonceBytes)
        let sealedBox = try ChaChaPoly.SealedBox(nonce: chaChaNonce, ciphertext: payload, tag: authTag)
        do {
            return try ChaChaPoly.open(sealedBox, using: symmetricKey)
        } catch {
            throw MeshKitCryptoError.decryptionFailed
        }
    }

    // MARK:- Verify

    /// Verify Ed25519 signature only (relay nodes use this).
    public func verifySignature() throws -> Bool {
        let toSign = signableBytes()
        return try MeshKitIdentity.verify(
            signature: signature,
            for: toSign,
            publicKey: fromSigningPublicKey
        )
    }

    // MARK:- Relay

    /// Increment hops. Returns false if hops >= ttl (drop the envelope).
    public mutating func relay() -> Bool {
        guard hops < ttl else { return false }
        hops += 1
        return true
    }

    // MARK:- Serialize

    /// Serialize to binary wire format.
    public func serialize() -> Data {
        var data = Data()
        data.append(Self.version)
        data.append(flags)
        appendLE(&data, appId)
        appendUUID(&data, fromNodeId)
        data.append(fromSigningPublicKey)

        if flags & Self.flagDirected != 0 {
            appendUUID(&data, toNodeId!)
            data.append(ephemeralPublicKey!)
        }

        appendLE(&data, timestamp)
        data.append(ttl)
        data.append(hops)
        appendLE(&data, UInt16(payload.count))

        if flags & Self.flagEncrypted != 0 {
            data.append(nonce!)
        }

        data.append(payload)

        if flags & Self.flagEncrypted != 0 {
            data.append(tag!)
        }

        data.append(signature)
        return data
    }

    // MARK:- Deserialize

    /// Deserialize from binary wire format.
    public static func deserialize(_ data: Data) throws -> MeshKitEnvelope {
        guard data.count >= 2 else { throw MeshKitCryptoError.invalidEnvelope }
        var offset = 0

        let ver = data[offset]; offset += 1
        guard ver == Self.version else { throw MeshKitCryptoError.invalidEnvelope }

        let flags = data[offset]; offset += 1
        let isDirected = (flags & flagDirected) != 0
        let isEncrypted = (flags & flagEncrypted) != 0

        guard data.count >= offset + 2 else { throw MeshKitCryptoError.invalidEnvelope }
        let appId = readLE16(data, offset); offset += 2

        guard data.count >= offset + 16 else { throw MeshKitCryptoError.invalidEnvelope }
        let fromNodeId = readUUID(data, offset); offset += 16

        guard data.count >= offset + 32 else { throw MeshKitCryptoError.invalidEnvelope }
        let fromPubKey = Data(data[offset..<offset+32]); offset += 32

        var toNodeId: UUID? = nil
        var ephemeralPub: Data? = nil
        if isDirected {
            guard data.count >= offset + 16 else { throw MeshKitCryptoError.invalidEnvelope }
            toNodeId = readUUID(data, offset); offset += 16

            guard data.count >= offset + 32 else { throw MeshKitCryptoError.invalidEnvelope }
            ephemeralPub = Data(data[offset..<offset+32]); offset += 32
        }

        guard data.count >= offset + 4 + 1 + 1 + 2 else { throw MeshKitCryptoError.invalidEnvelope }
        let ts = readLE32(data, offset); offset += 4
        let ttl = data[offset]; offset += 1
        let hops = data[offset]; offset += 1
        let payloadLen = Int(readLE16(data, offset)); offset += 2

        var nonceBytes: Data? = nil
        if isEncrypted {
            guard data.count >= offset + 12 else { throw MeshKitCryptoError.invalidEnvelope }
            nonceBytes = Data(data[offset..<offset+12]); offset += 12
        }

        guard data.count >= offset + payloadLen else { throw MeshKitCryptoError.invalidEnvelope }
        let payload = Data(data[offset..<offset+payloadLen]); offset += payloadLen

        var authTag: Data? = nil
        if isEncrypted {
            guard data.count >= offset + 16 else { throw MeshKitCryptoError.invalidEnvelope }
            authTag = Data(data[offset..<offset+16]); offset += 16
        }

        guard data.count >= offset + 64 else { throw MeshKitCryptoError.invalidEnvelope }
        let sig = Data(data[offset..<offset+64]); offset += 64

        return MeshKitEnvelope(
            flags: flags,
            appId: appId,
            fromNodeId: fromNodeId,
            fromSigningPublicKey: fromPubKey,
            toNodeId: toNodeId,
            ephemeralPublicKey: ephemeralPub,
            timestamp: ts,
            ttl: ttl,
            hops: hops,
            nonce: nonceBytes,
            payload: payload,
            tag: authTag,
            signature: sig
        )
    }

    // MARK:- Signable bytes

    /// Compute the bytes to sign: everything except the hops byte and trailing 64-byte signature.
    private func signableBytes() -> Data {
        let full = serialize()
        // Locate hops byte offset: after version(1) + flags(1) + appId(2) + fromNodeId(16) + fromPubKey(32)
        // + optional [toNodeId(16) + ephemeralPub(32)] + ts(4) + ttl(1)
        var hopsOffset = 1 + 1 + 2 + 16 + 32
        if flags & Self.flagDirected != 0 {
            hopsOffset += 16 + 32
        }
        hopsOffset += 4 + 1 // ts(4) + ttl(1)
        // hopsOffset now points at the hops byte

        // Remove hops byte and trailing 64-byte signature
        var signable = Data()
        signable.append(full[0..<hopsOffset])
        signable.append(full[(hopsOffset + 1)..<(full.count - 64)])
        return signable
    }

    // MARK:- Binary helpers

    private func appendLE(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendLE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private func appendUUID(_ data: inout Data, _ uuid: UUID) {
        withUnsafeBytes(of: uuid.uuid) { data.append(contentsOf: $0) }
    }

    private static func readLE16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readLE32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUUID(_ data: Data, _ offset: Int) -> UUID {
        data.subdata(in: offset..<offset+16).withUnsafeBytes {
            UUID(uuid: $0.loadUnaligned(as: uuid_t.self))
        }
    }
}
