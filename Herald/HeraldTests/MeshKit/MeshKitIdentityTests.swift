//
//  MeshKitIdentityTests.swift
//
//  Copyright 2026 MeshKit Contributors
//  SPDX-License-Identifier: Apache-2.0
//

import XCTest
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import MeshKit

class MeshKitIdentityTests: XCTestCase {

    // MARK:- Key generation

    func testKeyGeneration() {
        let identity = MeshKitIdentity()
        XCTAssertEqual(identity.signingPublicKey.count, 32)
        XCTAssertEqual(identity.agreementPublicKey.count, 32)
        XCTAssertEqual(identity.seed.count, 32)
    }

    // MARK:- Seed round-trip

    func testSeedRoundtrip() throws {
        let original = MeshKitIdentity()
        let restored = try MeshKitIdentity(seed: original.seed)
        XCTAssertEqual(original.seed, restored.seed)
        XCTAssertEqual(original.signingPublicKey, restored.signingPublicKey)
        XCTAssertEqual(original.agreementPublicKey, restored.agreementPublicKey)
    }

    // MARK:- Sign and verify

    func testSignAndVerify() throws {
        let identity = MeshKitIdentity()
        let data = Data("hello meshkit".utf8)
        let signature = try identity.sign(data)
        XCTAssertEqual(signature.count, 64)
        let valid = try MeshKitIdentity.verify(
            signature: signature,
            for: data,
            publicKey: identity.signingPublicKey
        )
        XCTAssertTrue(valid)
    }

    func testSignatureFailsWithWrongKey() throws {
        let alice = MeshKitIdentity()
        let bob = MeshKitIdentity()
        let data = Data("hello meshkit".utf8)
        let signature = try alice.sign(data)
        let valid = try MeshKitIdentity.verify(
            signature: signature,
            for: data,
            publicKey: bob.signingPublicKey
        )
        XCTAssertFalse(valid)
    }

    func testSignatureFailsWithTamperedData() throws {
        let identity = MeshKitIdentity()
        let data = Data("hello meshkit".utf8)
        let tampered = Data("goodbye meshkit".utf8)
        let signature = try identity.sign(data)
        let valid = try MeshKitIdentity.verify(
            signature: signature,
            for: tampered,
            publicKey: identity.signingPublicKey
        )
        XCTAssertFalse(valid)
    }

    // MARK:- Key agreement

    func testSharedSecretAgreement() throws {
        let alice = MeshKitIdentity()
        let bob = MeshKitIdentity()
        let secretAB = try alice.sharedSecret(with: bob.agreementPublicKey)
        let secretBA = try bob.sharedSecret(with: alice.agreementPublicKey)
        // SharedSecret doesn't conform to Equatable directly; derive symmetric keys and compare.
        let keyAB = secretAB.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 32
        )
        let keyBA = secretBA.hkdfDerivedSymmetricKey(
            using: SHA256.self, salt: Data(), sharedInfo: Data(), outputByteCount: 32
        )
        // Compare by using the keys to encrypt and cross-decrypt.
        let testData = Data("test".utf8)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 12))
        let sealed = try ChaChaPoly.seal(testData, using: keyAB, nonce: nonce)
        let opened = try ChaChaPoly.open(sealed, using: keyBA)
        XCTAssertEqual(opened, testData)
    }

    func testDeriveSymmetricKey() throws {
        let alice = MeshKitIdentity()
        let bob = MeshKitIdentity()
        let salt = Data("salt".utf8)
        let keyAB = try alice.deriveSymmetricKey(with: bob.agreementPublicKey, salt: salt)
        let keyBA = try bob.deriveSymmetricKey(with: alice.agreementPublicKey, salt: salt)
        // Keys should be equivalent — verify by encrypt/decrypt.
        let testData = Data("deterministic".utf8)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0x42, count: 12))
        let sealed = try ChaChaPoly.seal(testData, using: keyAB, nonce: nonce)
        let opened = try ChaChaPoly.open(sealed, using: keyBA)
        XCTAssertEqual(opened, testData)
    }
}
