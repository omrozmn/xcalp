import Foundation

extension DataRetentionCheck {
    // HIPAA requires medical records to be retained for at least 6 years
    private static let minimumRetentionPeriod: TimeInterval = 6 * 365 * 24 * 3600
    // Maximum retention to prevent unnecessary data accumulation
    private static let maximumRetentionPeriod: TimeInterval = 10 * 365 * 24 * 3600
    
    func validate<T: HIPAACompliant>(_ data: T) async throws {
        let now = Date()
        let creationDate = data.lastModified
        let age = now.timeIntervalSince(creationDate)
        
        // Check if data is within required retention period
        guard age >= 0 else {
            throw RetentionError.invalidCreationDate
        }
        
        // Check if data needs to be archived
        if age >= Self.minimumRetentionPeriod {
            try await archiveData(data)
        }
        
        // Check if data should be deleted
        if age >= Self.maximumRetentionPeriod {
            throw RetentionError.exceededRetentionPeriod
        }
        
        LoggingService.shared.logHIPAAEvent(
            "Data retention validation successful",
            type: .access,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "age": age,
                "creationDate": creationDate
            ]
        )
    }
    
    private func archiveData<T: HIPAACompliant>(_ data: T) async throws {
        // Archive data for long-term storage
        let archiveData = ArchiveMetadata(
            originalIdentifier: data.identifier,
            dataType: T.dataType,
            archiveDate: Date(),
            accessControl: data.accessControl
        )
        
        try await SecureStorageService.shared.store(
            archiveData,
            type: .systemConfig,
            identifier: "archive_\(data.identifier)"
        )
        
        LoggingService.shared.logHIPAAEvent(
            "Data archived for retention",
            type: .modification,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "archiveDate": archiveData.archiveDate
            ]
        )
    }
}

private struct ArchiveMetadata: Codable {
    let originalIdentifier: String
    let dataType: DataType
    let archiveDate: Date
    let accessControl: AccessControlLevel
}

enum RetentionError: LocalizedError {
    case invalidCreationDate
    case exceededRetentionPeriod
    
    var errorDescription: String? {
        switch self {
        case .invalidCreationDate:
            return "Invalid data creation date"
        case .exceededRetentionPeriod:
            return "Data has exceeded maximum retention period"
        }
    }
}
