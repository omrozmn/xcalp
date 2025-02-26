import Foundation
import CryptoKit

public actor StateIntegrityVerifier {
    private let secureStorage: SecureStorageService
    private let encryptionService: EncryptionService
    
    init(
        secureStorage: SecureStorageService = .shared,
        encryptionService: EncryptionService = .shared
    ) {
        self.secureStorage = secureStorage
        self.encryptionService = encryptionService
    }
    
    public func verify(_ state: AppState) async throws -> Bool {
        // Verify state signature
        guard try verifySignature(state) else {
            return false
        }
        
        // Verify data integrity
        guard try await verifyDataIntegrity(state) else {
            return false
        }
        
        // Verify version compatibility
        guard try verifyVersionCompatibility(state) else {
            return false
        }
        
        // Verify data consistency
        guard try await verifyDataConsistency(state) else {
            return false
        }
        
        return true
    }
    
    private func verifySignature(_ state: AppState) throws -> Bool {
        let computedHash = SHA256.hash(data: state.data)
        return computedHash == state.signature
    }
    
    private func verifyDataIntegrity(_ state: AppState) async throws -> Bool {
        // Verify encrypted data blocks
        for block in state.dataBlocks {
            guard try await verifyDataBlock(block) else {
                return false
            }
        }
        
        // Verify checksums
        guard try verifyChecksums(state) else {
            return false
        }
        
        // Verify sequential integrity
        guard try verifySequentialIntegrity(state) else {
            return false
        }
        
        return true
    }
    
    private func verifyVersionCompatibility(_ state: AppState) throws -> Bool {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let stateVersion = state.version
        
        // Check major version compatibility
        let currentMajor = Int(currentVersion.split(separator: ".")[0]) ?? 0
        let stateMajor = Int(stateVersion.split(separator: ".")[0]) ?? 0
        
        return currentMajor >= stateMajor
    }
    
    private func verifyDataConsistency(_ state: AppState) async throws -> Bool {
        // Verify entity relationships
        guard try await verifyEntityRelationships(state) else {
            return false
        }
        
        // Verify data dependencies
        guard try verifyDataDependencies(state) else {
            return false
        }
        
        // Verify state completeness
        guard try verifyStateCompleteness(state) else {
            return false
        }
        
        return true
    }
    
    private func verifyDataBlock(_ block: DataBlock) async throws -> Bool {
        // Decrypt block
        let decryptedData = try await secureStorage.performSecureOperation {
            try encryptionService.decrypt(block.data)
        }
        
        // Verify block integrity
        let computedHash = SHA256.hash(data: decryptedData)
        guard computedHash == block.hash else {
            return false
        }
        
        // Verify block sequence
        guard block.sequence == block.previousHash else {
            return false
        }
        
        return true
    }
    
    private func verifyChecksums(_ state: AppState) throws -> Bool {
        // Verify individual checksums
        for checksum in state.checksums {
            guard try verifyChecksum(checksum) else {
                return false
            }
        }
        
        // Verify checksum chain
        guard try verifyChecksumChain(state.checksums) else {
            return false
        }
        
        return true
    }
    
    private func verifySequentialIntegrity(_ state: AppState) throws -> Bool {
        // Verify timestamp sequence
        guard try verifyTimestampSequence(state) else {
            return false
        }
        
        // Verify operation sequence
        guard try verifyOperationSequence(state) else {
            return false
        }
        
        return true
    }
    
    private func verifyEntityRelationships(_ state: AppState) async throws -> Bool {
        // Verify database relationships
        for entity in state.entities {
            guard try await verifyEntity(entity) else {
                return false
            }
        }
        
        return true
    }
    
    private func verifyDataDependencies(_ state: AppState) throws -> Bool {
        // Verify all required dependencies exist
        guard try verifyRequiredDependencies(state) else {
            return false
        }
        
        // Verify dependency versions
        guard try verifyDependencyVersions(state) else {
            return false
        }
        
        return true
    }
    
    private func verifyStateCompleteness(_ state: AppState) throws -> Bool {
        // Verify all required components exist
        guard try verifyRequiredComponents(state) else {
            return false
        }
        
        // Verify state consistency
        guard try verifyStateConsistency(state) else {
            return false
        }
        
        return true
    }
}

// MARK: - Supporting Types

extension StateIntegrityVerifier {
    struct DataBlock {
        let sequence: Int
        let previousHash: SHA256.Digest
        let hash: SHA256.Digest
        let data: Data
    }
    
    struct Checksum {
        let blockId: UUID
        let hash: SHA256.Digest
        let timestamp: Date
    }
}

public struct AppState {
    let version: String
    let timestamp: Date
    let signature: SHA256.Digest
    let data: Data
    let dataBlocks: [StateIntegrityVerifier.DataBlock]
    let checksums: [StateIntegrityVerifier.Checksum]
    let entities: [NSManagedObjectID]
    let secureData: Data
    let sessionData: Data
}