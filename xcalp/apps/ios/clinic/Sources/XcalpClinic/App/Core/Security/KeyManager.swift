import Foundation
import Security
import CryptoKit

final class KeyManager {
    static let shared = KeyManager()
    private let errorHandler = XCErrorHandler.shared
    
    // Tag for app's key pair in Keychain
    private let applicationTag = "com.xcalp.clinic.keypair"
    private let keychainAccessGroup = "com.xcalp.clinic.security"
    
    private init() {
        ensureApplicationKeyPair()
    }
    
    // MARK: - Public Key Operations
    func getPublicKey() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnRef as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let publicKey = result as? SecKey else {
            throw KeyManagerError.publicKeyNotFound
        }
        
        return publicKey
    }
    
    func getPublicKeyData() throws -> Data {
        let publicKey = try getPublicKey()
        
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyExportFailed
        }
        
        return publicKeyData
    }
    
    // MARK: - Key Management
    func storeRecipientPublicKey(_ keyData: Data, for recipientId: String) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecValueData as String: keyData,
            kSecAttrApplicationTag as String: "\(applicationTag).\(recipientId)",
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw KeyManagerError.keyStoreFailed
        }
    }
    
    func getRecipientPublicKey(for recipientId: String) throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag as String: "\(applicationTag).\(recipientId)",
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnRef as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let publicKey = result as? SecKey else {
            throw KeyManagerError.recipientKeyNotFound
        }
        
        return publicKey
    }
    
    func removeRecipientKey(for recipientId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrApplicationTag as String: "\(applicationTag).\(recipientId)",
            kSecAttrAccessGroup as String: keychainAccessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.keyDeleteFailed
        }
    }
    
    // MARK: - Symmetric Key Operations
    func generateSymmetricKey() throws -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    func wrapSymmetricKey(_ symmetricKey: SymmetricKey, for recipientPublicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let wrappedKey = SecKeyCreateEncryptedData(
            recipientPublicKey,
            .rsaEncryptionOAEPSHA256,
            symmetricKey.withUnsafeBytes { Data($0) } as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyWrapFailed
        }
        
        return wrappedKey
    }
    
    func unwrapSymmetricKey(_ wrappedKey: Data, with privateKey: SecKey) throws -> SymmetricKey {
        var error: Unmanaged<CFError>?
        guard let unwrappedKeyData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            wrappedKey as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyUnwrapFailed
        }
        
        return SymmetricKey(data: unwrappedKeyData)
    }
    
    // MARK: - Private Methods
    private func ensureApplicationKeyPair() {
        do {
            _ = try getPublicKey()
        } catch {
            do {
                try generateNewKeyPair()
            } catch {
                errorHandler.handle(error, severity: .critical)
            }
        }
    }
    
    private func generateNewKeyPair() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: applicationTag,
                kSecAttrAccessGroup as String: keychainAccessGroup
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? KeyManagerError.keyGenerationFailed
        }
        
        _ = SecKeyCopyPublicKey(privateKey)
    }
}

enum KeyManagerError: Error {
    case publicKeyNotFound
    case privateKeyNotFound
    case recipientKeyNotFound
    case keyGenerationFailed
    case keyStoreFailed
    case keyDeleteFailed
    case keyExportFailed
    case keyWrapFailed
    case keyUnwrapFailed
    case invalidKeyData
}

// MARK: - SymmetricKey Extensions
extension SymmetricKey {
    init(data: Data) throws {
        guard data.count == SymmetricKeySize.bits256.bitCount / 8 else {
            throw KeyManagerError.invalidKeyData
        }
        self.init(data: data)
    }
}