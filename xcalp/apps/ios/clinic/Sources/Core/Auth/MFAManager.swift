import Core
import CryptoKit
import Foundation
import KeychainAccess

public enum MFAType: String, Codable {
    case authenticatorApp
    case sms
    case email
    case recoveryCode
}

public enum MFAError: LocalizedError {
    case invalidCode
    case expiredCode
    case tooManyAttempts
    case setupRequired
    case alreadyEnabled
    case invalidSecret
    case invalidRecoveryCode
    case noRecoveryCodesLeft
    
    public var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "Invalid verification code"
        case .expiredCode:
            return "Verification code has expired"
        case .tooManyAttempts:
            return "Too many invalid attempts"
        case .setupRequired:
            return "MFA setup required"
        case .alreadyEnabled:
            return "MFA is already enabled"
        case .invalidSecret:
            return "Invalid MFA secret"
        case .invalidRecoveryCode:
            return "Invalid recovery code"
        case .noRecoveryCodesLeft:
            return "No recovery codes left"
        }
    }
}

/// Manages multi-factor authentication for users.
public final class MFAManager {
    public static let shared = MFAManager()
    
    private let keychain = KeychainManager.shared
    private let logger = XcalpLogger.shared
    private let rateLimiter = RateLimitManager.shared
    private let codeLength = 6
    private let codeTTL: TimeInterval = 30 // TOTP time step in seconds
    private let recoveryCodeCount = 10
    private let recoveryCodeLength = 10
    
    private init() {}
    
    /// Sets up multi-factor authentication for a user.
    public func setupMFA(type: MFAType, for userID: String) async throws -> MFASetupResult {
        let secret = generateSecret()
        let recoveryCodes = generateRecoveryCodes()
        
        let config = MFAConfig(
            type: type,
            secret: secret,
            enabled: false,
            createdAt: Date(),
            recoveryCodes: recoveryCodes,
            lastBackupTimestamp: nil
        )
        try await storeMFAConfig(config, for: userID)
        
        return MFASetupResult(
            secret: secret,
            recoveryCodes: recoveryCodes
        )
    }
    
    /// Verifies the MFA code and enables MFA for the user.
    public func verifyAndEnableMFA(code: String, for userID: String) async throws {
        guard let config = try await getMFAConfig(for: userID) else {
            throw MFAError.setupRequired
        }
        
        guard !config.enabled else {
            throw MFAError.alreadyEnabled
        }
        
        guard rateLimiter.checkRateLimit(for: "mfa:\(userID)") else {
            throw MFAError.tooManyAttempts
        }
        
        let isValid = try await verifyCode(code, secret: config.secret, type: config.type)
        
        if isValid {
            var updatedConfig = config
            updatedConfig.enabled = true
            
            // Verify device trust level before enabling MFA
            let deviceManager = DeviceManager.shared
            let currentDevice = try await deviceManager.registerDevice()
            
            // Only allow MFA setup from trusted or provisional devices
            if currentDevice.trustLevel == .untrusted {
                throw DeviceError.trustLevelTooLow
            }
            
            // Update device trust level to trusted after successful MFA setup
            try await deviceManager.updateDeviceTrustLevel(currentDevice.id, trustLevel: .trusted)
            
            try await storeMFAConfig(updatedConfig, for: userID)
            rateLimiter.resetAttempts(for: "mfa:\(userID)")
            
            logger.info("MFA enabled for user: \(userID) from device: \(currentDevice.id)")
        } else {
            throw MFAError.invalidCode
        }
    }
    
    /// Verifies the MFA code for the user.
    public func verifyMFA(code: String, for userID: String) async throws {
        guard let config = try await getMFAConfig(for: userID) else {
            throw MFAError.setupRequired
        }
        
        guard config.enabled else {
            throw MFAError.setupRequired
        }
        
        guard rateLimiter.checkRateLimit(for: "mfa:\(userID)") else {
            throw MFAError.tooManyAttempts
        }
        
        // First check if it's a recovery code
        if let updatedConfig = try await verifyRecoveryCode(code, config: config) {
            try await storeMFAConfig(updatedConfig, for: userID)
            rateLimiter.resetAttempts(for: "mfa:\(userID)")
            logger.info("MFA verified with recovery code for user: \(userID)")
            return
        }
        
        // If not a recovery code, verify as TOTP code
        let isValid = try await verifyCode(code, secret: config.secret, type: config.type)
        
        if isValid {
            rateLimiter.resetAttempts(for: "mfa:\(userID)")
            logger.info("MFA verified with TOTP for user: \(userID)")
        } else {
            throw MFAError.invalidCode
        }
    }
    
    private func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base32EncodedString()
    }
    
    private func verifyCode(_ code: String, secret: String, type: MFAType) async throws -> Bool {
        switch type {
        case .authenticatorApp:
            return verifyTOTPCode(code, secret: secret)
        case .sms, .email:
            return await verifyStoredCode(code, for: secret)
        }
    }
    
    private func verifyRecoveryCode(_ code: String, config: MFAConfig) async throws -> MFAConfig? {
        guard !config.recoveryCodes.isEmpty else {
            return nil
        }
        
        guard let index = config.recoveryCodes.firstIndex(of: code) else {
            return nil
        }
        
        var updatedConfig = config
        updatedConfig.recoveryCodes.remove(at: index)
        return updatedConfig
    }
    
    private func generateRecoveryCodes() -> [String] {
        (0..<recoveryCodeCount).map { _ in
            var code = ""
            for _ in 0..<recoveryCodeLength {
                code += String(Int.random(in: 0...9))
            }
            return code
        }
    }
    
    private func verifyStoredCode(_ code: String, for secret: String) async -> Bool {
        // TODO: Implement stored code verification for SMS/Email
        // For now, just return false as we're focusing on authenticator app
        false
    }
    
    private func storeMFAConfig(_ config: MFAConfig, for userID: String) async throws {
        let data = try JSONEncoder().encode(config)
        try await keychain.store(data, forKey: "mfa_config:\(userID)")
    }
    
    private func getMFAConfig(for userID: String) async throws -> MFAConfig? {
        guard let data = try await keychain.retrieve(forKey: "mfa_config:\(userID)") else {
            return nil
        }
        return try JSONDecoder().decode(MFAConfig.self, from: data)
    }
    
    private func base32DecodeToData(_ encoded: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var value = 0
        var output = Data()
        
        for char in encoded.uppercased() {
            guard let charValue = alphabet.firstIndex(of: char)?.utf16Offset(in: alphabet) else {
                return nil
            }
            
            value = (value << 5) | charValue
            bits += 5
            
            while bits >= 8 {
                output.append(UInt8(value >> (bits - 8)))
                bits -= 8
            }
        }
        
        return output
    }
    
    private func generateTOTP(secret: Data, timeStep: UInt64) -> Int {
        var timeBytes = timeStep.bigEndian
        let timeData = Data(bytes: &timeBytes, count: MemoryLayout<UInt64>.size)
        
        let hmac = HMAC<SHA1>.authenticationCode(
            for: timeData,
            using: SymmetricKey(data: secret)
        )
        
        let hmacData = Data(hmac)
        let offset = Int(hmacData[hmacData.count - 1] & 0x0f)
        
        let truncatedHash = hmacData[offset...].prefix(4)
        var code = truncatedHash.withUnsafeBytes { pointer in
            pointer.load(as: UInt32.self).bigEndian
        }
        
        code = code & 0x7FFFFFFF
        code = code % UInt32(pow(10.0, Double(codeLength)))
        
        return Int(code)
    }
    
    private func verifyTOTPCode(_ code: String, secret: String) -> Bool {
        guard code.count == codeLength,
              let codeInt = Int(code),
              let secretData = base32DecodeToData(secret) else {
            return false
        }
        
        let currentTime = Date().timeIntervalSince1970
        
        // Check current and adjacent time steps to account for clock skew
        for offset in [-1, 0, 1] {
            let timeStep = UInt64((currentTime / self.timeStep).rounded(.down)) + UInt64(offset)
            let expectedCode = generateTOTP(secret: secretData, timeStep: timeStep)
            if expectedCode == codeInt {
                return true
            }
        }
        
        return false
    }
}

private struct MFAConfig: Codable {
    let type: MFAType
    let secret: String
    var enabled: Bool
    let createdAt: Date
    var recoveryCodes: [String]
    var lastBackupTimestamp: Date?
}

public struct MFASetupResult {
    public let secret: String
    public let recoveryCodes: [String]
}
