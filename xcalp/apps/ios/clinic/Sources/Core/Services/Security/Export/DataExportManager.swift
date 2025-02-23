import Foundation
import CryptoKit

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
        
        // Create export package
        let exportPackage = try await createExportPackage(
            data: protectedData,
            request: request,
            sensitivity: sensitivity
        )
        
        // Log export
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
        // TODO: Implement actual data loading from secure storage
        // This is a placeholder that should be replaced with actual implementation
        return Data()
    }
    
    private func createExportPackage(
        data: Data,
        request: ExportRequest,
        sensitivity: SensitivityLevel
    ) async throws -> ExportPackage {
        ExportPackage(
            data: data,
            metadata: ExportMetadata(
                timestamp: Date(),
                purpose: .patientRequest,
                sensitivity: sensitivity,
                exportedBy: AuthenticationService.shared.currentSession?.userID ?? "SYSTEM"
            )
        )
    }
}

public struct ExportRequest {
    let patientID: String
    let dataTypes: [String]
    let format: ExportFormat
    
    public init(patientID: String, dataTypes: [String], format: ExportFormat) {
        self.patientID = patientID
        self.dataTypes = dataTypes
        self.format = format
    }
}

public enum ExportFormat: String {
    case json = "JSON"
    case pdf = "PDF"
    case dicom = "DICOM"
}

public enum ExportError: LocalizedError {
    case rateLimitExceeded
    case invalidRequest
    case dataNotFound
    
    public var errorDescription: String? {
        switch self {
        case .rateLimitExceeded: return "Export rate limit exceeded for today"
        case .invalidRequest: return "Invalid export request"
        case .dataNotFound: return "Requested data not found"
        }
    }
}