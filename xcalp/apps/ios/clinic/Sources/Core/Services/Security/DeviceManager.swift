import Core
import CryptoKit
import Foundation
import UIKit

public struct Device: Codable, Equatable {
    public let id: String
    public let name: String
    public let model: String
    public let osVersion: String
    public let appVersion: String
    public let lastLoginAt: Date
    public var isCurrentDevice: Bool
    public var trustLevel: DeviceTrustLevel
    
    public enum DeviceTrustLevel: String, Codable {
        case trusted
        case provisional
        case untrusted
    }
}

public enum DeviceError: LocalizedError {
    case deviceLimitExceeded
    case deviceBlocked
    case deviceNotFound
    case trustLevelTooLow
    case cannotBlockLastTrustedDevice
    
    public var errorDescription: String? {
        switch self {
        case .deviceLimitExceeded: return "Maximum number of devices reached"
        case .deviceBlocked: return "Device has been blocked"
        case .deviceNotFound: return "Device not found"
        case .trustLevelTooLow: return "Device trust level too low for this operation"
        case .cannotBlockLastTrustedDevice: return "Cannot block the last trusted device"
        }
    }
}

public final class DeviceManager {
    public static let shared = DeviceManager()
    
    private let keychain = KeychainManager.shared
    private let logger = XcalpLogger.shared
    private let maxDevices = 5
    private let deviceKeyPrefix = "device:"
    
    private init() {}
    
    public func registerDevice(withMFAStatus mfaEnabled: Bool = false) async throws -> Device {
        let devices = try await getDevices()
        guard devices.count < maxDevices else {
            throw DeviceError.deviceLimitExceeded
        }
        
        // Check if this device was previously registered
        let deviceIdentifier = try await getDeviceIdentifier()
        if let existingDevice = try await findDeviceByIdentifier(deviceIdentifier) {
            return existingDevice
        }
        
        let initialTrustLevel: Device.DeviceTrustLevel = mfaEnabled ? .trusted : .provisional
        
        let device = Device(
            id: deviceIdentifier,
            name: UIDevice.current.name,
            model: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            lastLoginAt: Date(),
            isCurrentDevice: true,
            trustLevel: initialTrustLevel
        )
        
        try await storeDevice(device)
        logger.info("Device registered: \(device.id) with trust level: \(initialTrustLevel)")
        
        return device
    }
    
    public func updateDeviceTrustLevel(_ deviceId: String, trustLevel: Device.DeviceTrustLevel) async throws {
        guard var device = try await getDevice(deviceId) else {
            throw DeviceError.deviceNotFound
        }
        
        device.trustLevel = trustLevel
        try await storeDevice(device)
        
        logger.info("Device trust level updated: \(deviceId) -> \(trustLevel)")
    }
    
    public func updateLastLogin(_ deviceId: String) async throws {
        guard var device = try await getDevice(deviceId) else {
            throw DeviceError.deviceNotFound
        }
        
        let updatedDevice = Device(
            id: device.id,
            name: device.name,
            model: device.model,
            osVersion: device.osVersion,
            appVersion: device.appVersion,
            lastLoginAt: Date(),
            isCurrentDevice: device.isCurrentDevice,
            trustLevel: device.trustLevel
        )
        
        try await storeDevice(updatedDevice)
        logger.info("Updated last login for device: \(deviceId)")
    }
    
    public func blockDevice(_ deviceId: String) async throws {
        guard var device = try await getDevice(deviceId) else {
            throw DeviceError.deviceNotFound
        }
        
        // Don't allow blocking if this is the last trusted device
        let devices = try await getDevices()
        let trustedDevices = devices.filter { $0.trustLevel == .trusted }
        if trustedDevices.count == 1 && trustedDevices.first?.id == deviceId {
            throw DeviceError.cannotBlockLastTrustedDevice
        }
        
        let updatedDevice = Device(
            id: device.id,
            name: device.name,
            model: device.model,
            osVersion: device.osVersion,
            appVersion: device.appVersion,
            lastLoginAt: device.lastLoginAt,
            isCurrentDevice: device.isCurrentDevice,
            trustLevel: .untrusted
        )
        
        try await storeDevice(updatedDevice)
        logger.info("Device blocked: \(deviceId)")
    }
    
    public func removeDevice(_ deviceId: String) async throws {
        guard try await getDevice(deviceId) != nil else {
            throw DeviceError.deviceNotFound
        }
        
        try await keychain.remove("\(deviceKeyPrefix)\(deviceId)")
        logger.info("Device removed: \(deviceId)")
    }
    
    public func getDevices() async throws -> [Device] {
        let keys = try await keychain.allKeys().filter { $0.hasPrefix(deviceKeyPrefix) }
        var devices: [Device] = []
        
        for key in keys {
            if let data = try await keychain.retrieve(forKey: key),
               let device = try? JSONDecoder().decode(Device.self, from: data) {
                devices.append(device)
            }
        }
        
        return devices
    }
    
    public func validateDevice(_ deviceId: String, requiredTrustLevel: Device.DeviceTrustLevel) async throws {
        guard let device = try await getDevice(deviceId) else {
            throw DeviceError.deviceNotFound
        }
        
        let trustLevels: [Device.DeviceTrustLevel] = [.untrusted, .provisional, .trusted]
        guard let currentLevel = trustLevels.firstIndex(of: device.trustLevel),
              let requiredLevel = trustLevels.firstIndex(of: requiredTrustLevel),
              currentLevel >= requiredLevel else {
            throw DeviceError.trustLevelTooLow
        }
    }
    
    private func getDevice(_ deviceId: String) async throws -> Device? {
        guard let data = try await keychain.retrieve(forKey: "\(deviceKeyPrefix)\(deviceId)") else {
            return nil
        }
        return try JSONDecoder().decode(Device.self, from: data)
    }
    
    private func storeDevice(_ device: Device) async throws {
        let data = try JSONEncoder().encode(device)
        try await keychain.store(data, forKey: "\(deviceKeyPrefix)\(device.id)")
    }
    
    private func getDeviceIdentifier() async throws -> String {
        if let storedIdentifier = try? await keychain.retrieve(forKey: "device_identifier") {
            return storedIdentifier
        }
        
        let identifier = UUID().uuidString
        try await keychain.store(identifier, forKey: "device_identifier")
        return identifier
    }
    
    private func findDeviceByIdentifier(_ identifier: String) async throws -> Device? {
        let devices = try await getDevices()
        return devices.first { $0.id == identifier }
    }
}
