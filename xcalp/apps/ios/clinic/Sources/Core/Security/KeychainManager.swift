import Foundation
import Security

class KeychainManager {
    static let shared = KeychainManager()
    private let serviceIdentifier = "com.xcalp.clinic"
    private let encryptionKeyIdentifier = "encryption_key"
    
    private init() {}
    
    func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecAttrAccount as String: key
            ]
            
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            
            let updateStatus = SecItemUpdate(
                updateQuery as CFDictionary,
                updateAttributes as CFDictionary
            )
            
            guard updateStatus == errSecSuccess else {
                throw KeychainError.updateFailed(status: updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.saveFailed(status: status)
        }
    }
    
    func read(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status: status)
        }
        
        return result as? Data
    }
    
    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }
    
    func getEncryptionKey() throws -> Data? {
        // Try to read existing key
        if let existingKey = try? read(forKey: encryptionKeyIdentifier) {
            return existingKey
        }
        
        // Generate new key if none exists
        var keyData = Data(count: 32) // 256-bit key
        let result = keyData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        
        guard result == errSecSuccess else {
            throw KeychainError.keyGenerationFailed(status: result)
        }
        
        // Save the new key
        try save(keyData, forKey: encryptionKeyIdentifier)
        return keyData
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case updateFailed(status: OSStatus)
    case keyGenerationFailed(status: OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .readFailed(let status):
            return "Failed to read from Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        case .updateFailed(let status):
            return "Failed to update Keychain item: \(status)"
        case .keyGenerationFailed(let status):
            return "Failed to generate encryption key: \(status)"
        }
    }
}
