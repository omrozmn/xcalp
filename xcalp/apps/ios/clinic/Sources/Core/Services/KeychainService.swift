import Foundation
import Security

public actor KeychainService {
    public static let shared = KeychainService()
    
    private init() {}
    
    public func store(
        key: Data,
        service: String,
        label: String? = nil,
        accessGroup: String? = nil
    ) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: service,
            kSecValueData as String: key
        ]
        
        if let label = label {
            query[kSecAttrLabel as String] = label
        }
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // First try to delete any existing key
        SecItemDelete(query as CFDictionary)
        
        // Add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeError(status: status)
        }
    }
    
    public func load(
        service: String,
        accessGroup: String? = nil
    ) async throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: service,
            kSecReturnData as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess else {
            throw KeychainError.loadError(status: status)
        }
        
        return result as? Data
    }
    
    public func delete(
        service: String,
        accessGroup: String? = nil
    ) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: service
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteError(status: status)
        }
    }
    
    public func storeCredential(
        username: String,
        password: String,
        service: String,
        accessGroup: String? = nil
    ) async throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: username,
            kSecAttrService as String: service,
            kSecValueData as String: password.data(using: .utf8)!
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        // First try to delete any existing credential
        SecItemDelete(query as CFDictionary)
        
        // Add the new credential
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeError(status: status)
        }
    }
    
    public func loadCredential(
        username: String,
        service: String,
        accessGroup: String? = nil
    ) async throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: username,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]
        
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            throw KeychainError.loadError(status: status)
        }
        
        return password
    }
}

// MARK: - Types

extension KeychainService {
    public enum KeychainError: LocalizedError {
        case storeError(status: OSStatus)
        case loadError(status: OSStatus)
        case deleteError(status: OSStatus)
        
        public var errorDescription: String? {
            switch self {
            case .storeError(let status):
                return "Failed to store item in keychain: \(status)"
            case .loadError(let status):
                return "Failed to load item from keychain: \(status)"
            case .deleteError(let status):
                return "Failed to delete item from keychain: \(status)"
            }
        }
    }
}