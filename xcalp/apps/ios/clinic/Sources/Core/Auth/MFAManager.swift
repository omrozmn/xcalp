import Foundation
import CryptoKit

public enum MFAType: String, Codable {
    case authenticatorApp
    case sms
    case email
}

public enum MFAError: LocalizedError {
    case invalidCode
    case expiredCode
    case tooManyAttempts
    case setupRequired
    case alreadyEnabled
    case invalidSecret
    
    public var errorDescription: String? {
        switch self {
        case .invalidCode: return "Invalid verification code"
        case .expiredCode: return "Verification code has expired"
        case .tooManyAttempts: return "Too many invalid attempts"
        case .setupRequired: return "MFA setup required"
        case .alreadyEnabled: return "MFA is already enabled"
        case .invalidSecret: return "Invalid MFA secret"
        }
    }
}

public final class MFAManager {
    public static let shared = MFAManager()
    
    private let keychain = KeychainManager.shared
    private let logger = XcalpLogger.shared
    private let rateLimiter = RateLimitManager.shared
    
    private let codeLength = 6
    private let codeTTL: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    public func setupMFA(type: MFAType, for userID: String) async throws -> String {
        // Generate a new secret key for the user
        let secret = generateSecret()
        
        // Store MFA configuration
        let config = MFAConfig(
            type: type,
            secret: secret,
            enabled: false,
            createdAt: Date()
        )
        try await storeMFAConfig(config, for: userID)
        
        // For authenticator apps, return the secret for QR code generation
        // For SMS/email, this would trigger sending the verification code
        return type == .authenticatorApp ? secret : ""
    }
    
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
        
        // Verify the code based on MFA type
        let isValid = try await verifyCode(code, secret: config.secret, type: config.type)
        
        if isValid {
            var updatedConfig = config
            updatedConfig.enabled = true
            try await storeMFAConfig(updatedConfig, for: userID)
            rateLimiter.resetAttempts(for: "mfa:\(userID)")
            
            logger.info("MFA enabled for user: \(userID)")
        } else {
            throw MFAError.invalidCode
        }
    }
    
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
        
        let isValid = try await verifyCode(code, secret: config.secret, type: config.type)
        
        if isValid {
            rateLimiter.resetAttempts(for: "mfa:\(userID)")
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
    
    private func verifyTOTPCode(_ code: String, secret: String) -> Bool {
        // TODO: Implement TOTP verification using RFC 6238
        // For now, just compare with a stored code
        return code == "123456"
    }
    
    private func verifyStoredCode(_ code: String, for secret: String) async -> Bool {
        // TODO: Implement stored code verification
        return code == "123456"
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
}

private struct MFAConfig: Codable {
    let type: MFAType
    let secret: String
    var enabled: Bool
    let createdAt: Date
}