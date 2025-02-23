import Foundation
import KeychainAccess

public final class KeychainManager {
    public static let shared = KeychainManager()
    private let keychain: Keychain
    private let logger = XcalpLogger.shared
    
    private init() {
        self.keychain = Keychain(service: "com.xcalp.clinic")
            .accessibility(.whenUnlockedThisDeviceOnly)
    }
    
    public func store(_ data: Data, forKey key: String) throws {
        do {
            try keychain.set(data, key: key)
            logger.info("Successfully stored data for key: \(key)")
        } catch {
            logger.error("Failed to store data for key: \(key), error: \(error)")
            throw SecurityError.keychainAccess("Failed to store data: \(error.localizedDescription)")
        }
    }
    
    public func retrieve(forKey key: String) throws -> Data {
        do {
            guard let data = try keychain.getData(key) else {
                throw SecurityError.keychainAccess("No data found for key: \(key)")
            }
            logger.info("Successfully retrieved data for key: \(key)")
            return data
        } catch {
            logger.error("Failed to retrieve data for key: \(key), error: \(error)")
            throw SecurityError.keychainAccess("Failed to retrieve data: \(error.localizedDescription)")
        }
    }
    
    public func remove(forKey key: String) throws {
        do {
            try keychain.remove(key)
            logger.info("Successfully removed data for key: \(key)")
        } catch {
            logger.error("Failed to remove data for key: \(key), error: \(error)")
            throw SecurityError.keychainAccess("Failed to remove data: \(error.localizedDescription)")
        }
    }
    
    public func removeAll() throws {
        do {
            try keychain.removeAll()
            logger.info("Successfully removed all keychain items")
        } catch {
            logger.error("Failed to remove all keychain items, error: \(error)")
            throw SecurityError.keychainAccess("Failed to remove all items: \(error.localizedDescription)")
        }
    }
}

public enum SecurityError: LocalizedError {
    case keychainAccess(String)
    
    public var errorDescription: String? {
        switch self {
        case .keychainAccess(let message):
            return message
        }
    }
}
