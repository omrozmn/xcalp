import CryptoKit
import Foundation
import KeychainAccess

public final class HIPAAEncryptionService {
    public static let shared = HIPAAEncryptionService()
    
    private let keychain = Keychain(service: "com.xcalp.clinic.hipaa")
    private let logger = LoggingService.shared
    
    private init() {
        setupEncryption()
    }
    
    private func setupEncryption() {
        do {
            // Ensure master key exists
            if try keychain.contains("master_key") == false {
                let masterKey = SymmetricKey(size: .bits256)
                let masterKeyData = masterKey.withUnsafeBytes { Data($0) }
                try keychain.set(masterKeyData, key: "master_key")
                
                logger.logSecurityEvent(
                    "Master encryption key generated",
                    level: .info,
                    metadata: ["keySize": "256"]
                )
            }
        } catch {
            logger.logSecurityEvent(
                "Failed to setup encryption",
                level: .critical,
                metadata: ["error": error.localizedDescription]
            )
        }
    }
    
    public func encrypt(_ data: Data, type: DataType) throws -> EncryptedData {
        let masterKey = try getMasterKey()
        let dataKey = SymmetricKey(size: .bits256)
        
        // Encrypt the actual data with data key
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: dataKey, nonce: nonce)
        
        // Encrypt the data key with master key
        let dataKeyBox = try AES.GCM.seal(dataKey.withUnsafeBytes { Data($0) }, using: masterKey)
        
        let encrypted = EncryptedData(
            data: sealedBox.combined!,
            dataKey: dataKeyBox.combined!,
            type: type,
            timestamp: Date()
        )
        
        logger.logHIPAAEvent(
            "Data encrypted",
            type: .modification,
            metadata: [
                "type": type.rawValue,
                "size": data.count
            ]
        )
        
        return encrypted
    }
    
    public func decrypt(_ encrypted: EncryptedData) throws -> Data {
        let masterKey = try getMasterKey()
        
        // Decrypt the data key
        let sealedDataKey = try AES.GCM.SealedBox(combined: encrypted.dataKey)
        let dataKeyData = try AES.GCM.open(sealedDataKey, using: masterKey)
        let dataKey = SymmetricKey(data: dataKeyData)
        
        // Decrypt the actual data
        let sealedData = try AES.GCM.SealedBox(combined: encrypted.data)
        let decryptedData = try AES.GCM.open(sealedData, using: dataKey)
        
        logger.logHIPAAEvent(
            "Data decrypted",
            type: .access,
            metadata: [
                "type": encrypted.type.rawValue,
                "size": decryptedData.count
            ]
        )
        
        return decryptedData
    }
    
    private func getMasterKey() throws -> SymmetricKey {
        guard let masterKeyData = try keychain.getData("master_key") else {
            throw SecurityError.masterKeyMissing
        }
        return SymmetricKey(data: masterKeyData)
    }
}

public struct EncryptedData: Codable {
    let data: Data
    let dataKey: Data
    let type: DataType
    let timestamp: Date
    
    public var metadata: [String: Any] {
        [
            "type": type.rawValue,
            "timestamp": timestamp,
            "size": data.count
        ]
    }
}

public enum DataType: String, Codable {
    case patientInfo
    case scanData
    case treatmentPlan
    case analytics
    case systemConfig
}

public enum SecurityError: LocalizedError {
    case masterKeyMissing
    case encryptionFailed
    case decryptionFailed
    
    public var errorDescription: String? {
        switch self {
        case .masterKeyMissing:
            return "Master encryption key not found"
        case .encryptionFailed:
            return "Failed to encrypt data"
        case .decryptionFailed:
            return "Failed to decrypt data"
        }
    }
}
