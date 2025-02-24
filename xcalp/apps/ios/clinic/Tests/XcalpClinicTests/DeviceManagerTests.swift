@testable import XcalpClinic
import XCTest

final class DeviceManagerTests: XCTestCase {
    var deviceManager: DeviceManager!
    
    override func setUp() {
        super.setUp()
        deviceManager = DeviceManager.shared
    }
    
    func testDeviceRegistration() async throws {
        // Test basic device registration
        let device = try await deviceManager.registerDevice()
        XCTAssertEqual(device.trustLevel, .provisional)
        
        // Test MFA-enabled registration
        let mfaDevice = try await deviceManager.registerDevice(withMFAStatus: true)
        XCTAssertEqual(mfaDevice.trustLevel, .trusted)
        
        // Verify device persistence
        let devices = try await deviceManager.getDevices()
        XCTAssertTrue(devices.contains { $0.id == device.id })
    }
    
    func testDeviceLimitEnforcement() async throws {
        // Try to register more than max allowed devices
        for _ in 0..<5 {
            _ = try await deviceManager.registerDevice()
        }
        
        do {
            _ = try await deviceManager.registerDevice()
            XCTFail("Should throw deviceLimitExceeded")
        } catch {
            XCTAssertEqual(error as? DeviceError, .deviceLimitExceeded)
        }
    }
    
    func testDeviceBlocking() async throws {
        // Register two devices
        let device1 = try await deviceManager.registerDevice(withMFAStatus: true)
        let device2 = try await deviceManager.registerDevice(withMFAStatus: true)
        
        // Block one device
        try await deviceManager.blockDevice(device2.id)
        
        // Verify device is blocked
        let devices = try await deviceManager.getDevices()
        let blockedDevice = devices.first { $0.id == device2.id }
        XCTAssertEqual(blockedDevice?.trustLevel, .untrusted)
        
        // Try to block last trusted device
        do {
            try await deviceManager.blockDevice(device1.id)
            XCTFail("Should throw cannotBlockLastTrustedDevice")
        } catch {
            XCTAssertEqual(error as? DeviceError, .cannotBlockLastTrustedDevice)
        }
    }
    
    func testDeviceTrustLevelValidation() async throws {
        let device = try await deviceManager.registerDevice()
        
        // Test provisional access
        try await deviceManager.validateDevice(device.id, requiredTrustLevel: .provisional)
        
        // Test trusted access (should fail for provisional device)
        do {
            try await deviceManager.validateDevice(device.id, requiredTrustLevel: .trusted)
            XCTFail("Should throw trustLevelTooLow")
        } catch {
            XCTAssertEqual(error as? DeviceError, .trustLevelTooLow)
        }
        
        // Update to trusted and verify
        try await deviceManager.updateDeviceTrustLevel(device.id, trustLevel: .trusted)
        try await deviceManager.validateDevice(device.id, requiredTrustLevel: .trusted)
    }
    
    func testDeviceLoginTracking() async throws {
        let device = try await deviceManager.registerDevice()
        let initialLogin = device.lastLoginAt
        
        // Wait a bit to ensure time difference
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Update login time
        try await deviceManager.updateLastLogin(device.id)
        
        // Verify login time was updated
        let updatedDevice = try await deviceManager.getDevices().first { $0.id == device.id }
        XCTAssertNotNil(updatedDevice)
        XCTAssertGreaterThan(updatedDevice!.lastLoginAt, initialLogin)
    }
}
