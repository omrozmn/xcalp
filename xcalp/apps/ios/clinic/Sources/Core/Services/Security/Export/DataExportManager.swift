import CryptoKit
import Foundation
import HIPAAMedicalDataHandler

public final class DataExportManager {
    public static let shared = DataExportManager()
    
    private let hipaaHandler = HIPAAMedicalDataHandler.shared
    private let logger = HIPAALogger.shared
    private let maxExportsPerDay = 10
    private var exportCounts: [String: (count: Int, date: Date)] = [:]
    
    private init() {}
    
    public func exportData(_ request: ExportRequest) async throws -> Data {
        // Verify rate limits
        try checkRateLimit(for: request.patientID)
        
        // Load and validate data
        let data = try await loadData(for: request)
        let sensitivity = try hipaaHandler.validateSensitivity(of: data)
        
        // Apply HIPAA-compliant protection
        let protectedData = try hipaaHandler.applyProtection(to: data, level: sensitivity)
        
        // Generate export package with metadata
        let exportPackage = ExportPackage(
            data: protectedData,
            metadata: ExportMetadata(
                timestamp: Date(),
                purpose: request.purpose,
                sensitivity: sensitivity,
                exportedBy: SessionManager.shared.currentSession?.userID ?? "SYSTEM"
            )
        )
        
        // Log export event
        logger.log(
            type: .export,
            action: "Data Export",
            userID: request.patientID,
            details: "Format: \(request.format.rawValue), Types: \(request.dataTypes.joined(separator: ","))"
        )
        
        return try JSONEncoder().encode(exportPackage)
    }
    
    public func verifyExport(_ exportData: Data) throws -> Bool {
        // Decode and verify export package
        let package = try JSONDecoder().decode(ExportPackage.self, from: exportData)
        return try hipaaHandler.verifyAndValidateExport(package.data)
    }
    
    private func checkRateLimit(for patientID: String) throws {
        let now = Date()
        if let lastExport = exportCounts[patientID] {
            if Calendar.current.isDate(lastExport.date, inSameDayAs: now) {
                guard lastExport.count < maxExportsPerDay else {
                    throw ExportError.rateLimitExceeded
                }
                exportCounts[patientID] = (lastExport.count + 1, now)
            } else {
                exportCounts[patientID] = (1, now)
            }
        } else {
            exportCounts[patientID] = (1, now)
        }
    }
    
    private func loadData(for request: ExportRequest) async throws -> Data {
        guard let session = SessionManager.shared.currentSession,
              AccessControlService.shared.validateAccess(for: .exportData) else {
            throw SecurityError.unauthorizedAccess
        }
        
        let storage = SecureStorageService.shared
        var exportData = Data()
        
        for dataType in request.dataTypes {
            // Load data from secure storage
            let data = try await storage.retrieve(
                type: DataType(rawValue: dataType) ?? .patientInfo,
                identifier: request.patientID
            )
            
            // Log access for HIPAA compliance
            logger.log(
                type: .access,
                action: "Export Data Access",
                userID: session.userID,
                details: "Data type: \(dataType), Patient: \(request.patientID)"
            )
            
            // Append to export data
            exportData.append(data)
        }
        
        guard !exportData.isEmpty else {
            throw ExportError.dataNotFound
        }
        
        return exportData
    }
}

public struct ExportRequest {
    let patientID: String
    let dataTypes: [String]
    let format: ExportFormat
    let purpose: HIPAAMedicalDataHandler.ExportPurpose
    
    public init(patientID: String, dataTypes: [String], format: ExportFormat, purpose: HIPAAMedicalDataHandler.ExportPurpose) {
        self.patientID = patientID
        self.dataTypes = dataTypes
        self.format = format
        self.purpose = purpose
    }
}

public enum ExportFormat: String {
    case json = "JSON"
    case pdf = "PDF"
}

public enum ExportError: LocalizedError {
    case rateLimitExceeded
    case invalidRequest
    case dataNotFound
    
    public var errorDescription: String? {
        switch self {
        case .rateLimitExceeded:
            return "Export rate limit exceeded for today"
        case .invalidRequest:
            return "Invalid export request"
        case .dataNotFound:
            return "Requested data not found"
        }
    }
}
