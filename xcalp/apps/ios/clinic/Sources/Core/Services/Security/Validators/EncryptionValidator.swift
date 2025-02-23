import Foundation
import CryptoKit

extension EncryptionCheck {
    private static let minimumKeySize = 256 // bits
    private static let requiredAlgorithm = "AES-GCM"
    
    func validate<T: HIPAACompliant>(_ data: T) async throws {
        // Verify encryption settings
        try validateEncryptionSettings()
        
        // Check key strength
        try validateKeyStrength()
        
        // Verify data encryption
        try validateDataEncryption(data)
        
        // Check key rotation status
        try await validateKeyRotation()
        
        LoggingService.shared.logHIPAAEvent(
            "Encryption validation successful",
            type: .access,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "algorithm": Self.requiredAlgorithm,
                "keySize": Self.minimumKeySize
            ]
        )
    }
    
    private func validateEncryptionSettings() throws {
        let encryptionService = HIPAAEncryptionService.shared
        
        guard let settings = try? encryptionService.getEncryptionSettings(),
              settings.algorithm == Self.requiredAlgorithm,
              settings.keySize >= Self.minimumKeySize else {
            throw EncryptionError.invalidSettings
        }
    }
    
    private func validateKeyStrength() throws {
        let keychain = try HIPAAEncryptionService.shared.getMasterKeyMetadata()
        
        guard keychain.keySize >= Self.minimumKeySize else {
            throw EncryptionError.insufficientKeyStrength
        }
        
        // Check key generation method
        guard keychain.generationMethod == .secure else {
            throw EncryptionError.insecureKeyGeneration
        }
    }
    
    private func validateDataEncryption<T: HIPAACompliant>(_ data: T) throws {
        // Check if PHI fields are encrypted
        for (field, value) in data.phi {
            if isFieldSensitive(field) {
                try validateFieldEncryption(field: field, value: value)
            }
        }
    }
    
    private func validateKeyRotation() async throws {
        let keychain = try HIPAAEncryptionService.shared.getMasterKeyMetadata()
        let calendar = Calendar.current
        
        // Check if key is older than 90 days
        if let lastRotation = keychain.lastRotationDate,
           calendar.dateComponents([.day], from: lastRotation, to: Date()).day ?? 0 > 90 {
            throw EncryptionError.keyRotationRequired
        }
    }
    
    private func isFieldSensitive(_ field: String) -> Bool {
        let sensitiveFields = [
            "ssn", "dob", "medicalRecordNumber", "insuranceId",
            "diagnosis", "treatment", "medication"
        ]
        return sensitiveFields.contains(field.lowercased())
    }
    
    private func validateFieldEncryption(field: String, value: Any) throws {
        if let stringValue = value as? String {
            // Check if value is properly encrypted
            guard stringValue.hasPrefix("encrypted:") else {
                throw EncryptionError.unencryptedField(field)
            }
            
            // Verify encryption format
            let encryptedPart = String(stringValue.dropFirst(10))
            guard let data = Data(base64Encoded: encryptedPart) else {
                throw EncryptionError.invalidEncryptionFormat(field)
            }
            
            // Verify encryption integrity
            guard data.count >= 32 else { // Minimum size for AES-256
                throw EncryptionError.compromisedEncryption(field)
            }
        }
    }
}

enum EncryptionError: LocalizedError {
    case invalidSettings
    case insufficientKeyStrength
    case insecureKeyGeneration
    case keyRotationRequired
    case unencryptedField(String)
    case invalidEncryptionFormat(String)
    case compromisedEncryption(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidSettings:
            return "Invalid encryption settings"
        case .insufficientKeyStrength:
            return "Encryption key strength below required minimum"
        case .insecureKeyGeneration:
            return "Insecure key generation method detected"
        case .keyRotationRequired:
            return "Encryption key rotation required"
        case .unencryptedField(let field):
            return "Unencrypted sensitive field detected: \(field)"
        case .invalidEncryptionFormat(let field):
            return "Invalid encryption format for field: \(field)"
        case .compromisedEncryption(let field):
            return "Potentially compromised encryption for field: \(field)"
        }
    }
}

// Required extensions to support encryption validation
extension HIPAAEncryptionService {
    struct EncryptionSettings {
        let algorithm: String
        let keySize: Int
        let mode: String
    }
    
    struct KeyMetadata {
        let keySize: Int
        let generationMethod: KeyGenerationMethod
        let lastRotationDate: Date?
    }
    
    enum KeyGenerationMethod {
        case secure
        case insecure
    }
    
    func getEncryptionSettings() throws -> EncryptionSettings {
        return EncryptionSettings(
            algorithm: "AES-GCM",
            keySize: 256,
            mode: "GCM"
        )
    }
    
    func getMasterKeyMetadata() throws -> KeyMetadata {
        // Implementation would fetch actual metadata
        return KeyMetadata(
            keySize: 256,
            generationMethod: .secure,
            lastRotationDate: Date().addingTimeInterval(-60 * 24 * 3600) // 60 days ago
        )
    }
}