//
//  MeshKitIdentity.swift
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

/// Persistent cryptographic identity for a MeshKit node.
///
/// Holds two key pairs derived from a single 32-byte seed:
/// - Ed25519 signing key (for envelope signatures)
/// - X25519 key agreement key (for ECDH key exchange + ChaCha20-Poly1305 encryption)
public class MeshKitIdentity {

    // MARK:- Private keys

    private let signingKey: Curve25519.Signing.PrivateKey
    private let agreementKey: Curve25519.KeyAgreement.PrivateKey

    /// The 32-byte seed from which both key pairs are derived. Store this for recovery.
    public let seed: Data

    // MARK:- Public keys (32 bytes each)

    /// Raw 32-byte Ed25519 public key for signature verification.
    public var signingPublicKey: Data { Data(signingKey.publicKey.rawRepresentation) }

    /// Raw 32-byte X25519 public key for envelope encryption.
    public var agreementPublicKey: Data { Data(agreementKey.publicKey.rawRepresentation) }

    // MARK:- Init

    /// Generate a new random identity.
    public init() {
        let signingKey = Curve25519.Signing.PrivateKey()
        self.seed = Data(signingKey.rawRepresentation)
        self.signingKey = signingKey
        self.agreementKey = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: self.seed)
    }

    /// Restore from a previously stored 32-byte seed.
    public init(seed: Data) throws {
        guard seed.count == 32 else { throw MeshKitCryptoError.invalidKeySize }
        self.seed = seed
        self.signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        self.agreementKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: seed)
    }

    // MARK:- Sign / Verify

    /// Sign data with Ed25519.
    public func sign(_ data: Data) throws -> Data {
        Data(try signingKey.signature(for: data))
    }

    /// Verify an Ed25519 signature given the signer's public key.
    public static func verify(signature: Data, for data: Data, publicKey: Data) throws -> Bool {
        let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        return pubKey.isValidSignature(signature, for: data)
    }

    // MARK:- Key Agreement

    /// ECDH shared secret with a peer's X25519 public key.
    public func sharedSecret(with peerAgreementPublicKey: Data) throws -> SharedSecret {
        let peerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerAgreementPublicKey)
        return try agreementKey.sharedSecretFromKeyAgreement(with: peerKey)
    }

    /// Derive a 256-bit symmetric key from ECDH shared secret using HKDF-SHA256.
    public func deriveSymmetricKey(
        with peerAgreementPublicKey: Data,
        salt: Data,
        info: Data = Data("meshkit-v1".utf8)
    ) throws -> SymmetricKey {
        let shared = try sharedSecret(with: peerAgreementPublicKey)
        return shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: info,
            outputByteCount: 32
        )
    }
}

// MARK:- Errors

public enum MeshKitCryptoError: Error {
    case invalidKeySize
    case invalidEnvelope
    case signatureVerificationFailed
    case decryptionFailed
    case payloadTooLarge
}
