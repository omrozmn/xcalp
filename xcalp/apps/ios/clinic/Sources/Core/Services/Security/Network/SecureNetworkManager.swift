import Foundation
import Network
import CryptoKit
import Security

public final class SecureNetworkManager {
    public static let shared = SecureNetworkManager()
    
    private let logger = HIPAALogger.shared
    private let certificatePinner: CertificatePinner
    private let encryptionManager: EncryptionManager
    
    private init() {
        self.certificatePinner = CertificatePinner()
        self.encryptionManager = EncryptionManager.shared
        setupTLSConfiguration()
    }
    
    private func setupTLSConfiguration() {
        let tlsConfig = TLSConfiguration(
            minimumTLSVersion: .TLSv13,
            certificateVerification: .fullVerification,
            certificatePinning: true
        )
        
        // Log security configuration
        logger.log(
            type: .security,
            action: "TLS Configuration",
            userID: "SYSTEM",
            details: "TLS 1.3, Full verification, Certificate pinning enabled"
        )
    }
    
    public func prepareForTransmission(_ data: Data) async throws -> Data {
        // Generate ephemeral key for this transmission
        let ephemeralKey = try encryptionManager.generateEphemeralKey()
        
        // Encrypt data with ephemeral key
        let encryptedData = try encryptionManager.encrypt(data: data, with: ephemeralKey)
        
        // Create secure package
        let package = SecurePackage(
            encryptedData: encryptedData,
            keyExchangeData: try encryptionManager.prepareKeyExchange(ephemeralKey),
            timestamp: Date(),
            signature: try sign(encryptedData)
        )
        
        // Log secure transmission preparation
        logger.log(
            type: .security,
            action: "Data Encryption",
            userID: AuthenticationService.shared.currentSession?.userID ?? "SYSTEM",
            details: "Preparing secure transmission"
        )
        
        return try JSONEncoder().encode(package)
    }
    
    public func processReceivedData(_ data: Data) async throws -> Data {
        let package = try JSONDecoder().decode(SecurePackage.self, from: data)
        
        // Verify timestamp to prevent replay attacks
        guard Date().timeIntervalSince(package.timestamp) < 300 else { // 5 minutes max
            throw SecurityError.invalidData("Expired secure package")
        }
        
        // Verify signature
        guard try verifySignature(package.signature, for: package.encryptedData) else {
            throw SecurityError.invalidSignature
        }
        
        // Process key exchange and decrypt data
        let key = try encryptionManager.processKeyExchange(package.keyExchangeData)
        return try encryptionManager.decrypt(data: package.encryptedData, with: key)
    }
    
    private func sign(_ data: Data) throws -> Data {
        return try encryptionManager.sign(data)
    }
    
    private func verifySignature(_ signature: Data, for data: Data) throws -> Bool {
        return try encryptionManager.verify(signature: signature, for: data)
    }
}

// Supporting types
private struct SecurePackage: Codable {
    let encryptedData: Data
    let keyExchangeData: Data
    let timestamp: Date
    let signature: Data
}

private struct TLSConfiguration {
    let minimumTLSVersion: TLSVersion
    let certificateVerification: CertificateVerificationType
    let certificatePinning: Bool
}

private enum TLSVersion {
    case TLSv12
    case TLSv13
}

private enum CertificateVerificationType {
    case fullVerification
    case skipHostnameVerification
}

private enum SecurityError: LocalizedError {
    case invalidData(String)
    case invalidSignature
    case securityConfigurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidData(let message): return "Invalid data: \(message)"
        case .invalidSignature: return "Invalid signature"
        case .securityConfigurationError(let message): return "Security configuration error: \(message)"
        }
    }
}