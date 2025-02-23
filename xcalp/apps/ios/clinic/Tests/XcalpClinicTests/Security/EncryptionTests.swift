import XCTest
import CryptoKit
import ComposableArchitecture
@testable import XcalpClinic

final class EncryptionTests: XCTestCase {
    func testDataAtRestEncryption() throws {
        let testData = "Sensitive Patient Data".data(using: .utf8)!
        let encryptionManager = EncryptionManager.shared
        
        // Test key generation
        let key = try encryptionManager.generateEncryptionKey()
        XCTAssertEqual(key.count, 32) // 256-bit key
        
        // Test encryption
        let encrypted = try encryptionManager.encrypt(data: testData, with: key)
        XCTAssertNotEqual(encrypted, testData)
        
        // Test decryption
        let decrypted = try encryptionManager.decrypt(data: encrypted, with: key)
        XCTAssertEqual(decrypted, testData)
        
        // Test key storage
        try encryptionManager.storeKey(key, identifier: "test-key")
        let retrievedKey = try encryptionManager.retrieveKey(identifier: "test-key")
        XCTAssertEqual(key, retrievedKey)
    }
    
    func testDataInTransitEncryption() async throws {
        let networkManager = SecureNetworkManager.shared
        let testData = "Test Data".data(using: .utf8)!
        
        // Test TLS configuration
        let config = networkManager.getTLSConfiguration()
        XCTAssertTrue(config.minimumTLSVersion == .TLSv12)
        XCTAssertTrue(config.certificatePinningEnabled)
        
        // Test secure transmission
        let encrypted = try await networkManager.prepareForTransmission(data: testData)
        XCTAssertNotEqual(encrypted, testData)
        
        // Test certificate pinning
        XCTAssertNoThrow(try networkManager.validateServerCertificate())
    }
    
    func testKeyRotation() async throws {
        let keyManager = KeyRotationManager.shared
        
        // Test key generation and rotation
        let initialKey = try keyManager.getCurrentKey()
        try await keyManager.rotateKeys()
        let newKey = try keyManager.getCurrentKey()
        XCTAssertNotEqual(initialKey, newKey)
        
        // Test key history
        let history = try keyManager.getKeyHistory()
        XCTAssertTrue(history.contains(initialKey))
        XCTAssertTrue(history.contains(newKey))
        
        // Test data re-encryption after rotation
        let testData = "Test Data".data(using: .utf8)!
        let encrypted = try keyManager.encryptWithCurrentKey(data: testData)
        try await keyManager.rotateKeys()
        let decrypted = try keyManager.decryptWithLatestKey(data: encrypted)
        XCTAssertEqual(decrypted, testData)
    }
    
    func testSecureRandomization() throws {
        let randomizer = SecureRandomizer.shared
        
        // Test random data generation
        let random1 = try randomizer.generateSecureRandomData(length: 32)
        let random2 = try randomizer.generateSecureRandomData(length: 32)
        XCTAssertNotEqual(random1, random2)
        XCTAssertEqual(random1.count, 32)
        
        // Test entropy
        let entropy = try randomizer.measureEntropy(of: random1)
        XCTAssertGreaterThan(entropy, 7.5) // Good entropy should be close to 8 bits per byte
    }
    
    func testEncryptedStorage() async throws {
        let storage = EncryptedStorageManager.shared
        let testData = "Sensitive Data".data(using: .utf8)!
        
        // Test secure storage
        try await storage.store(data: testData, key: "test")
        let retrieved = try await storage.retrieve(key: "test")
        XCTAssertEqual(retrieved, testData)
        
        // Test data isolation
        XCTAssertThrowsError(try await storage.retrieve(key: "nonexistent"))
        
        // Test secure deletion
        try await storage.delete(key: "test")
        XCTAssertThrowsError(try await storage.retrieve(key: "test"))
    }
}
