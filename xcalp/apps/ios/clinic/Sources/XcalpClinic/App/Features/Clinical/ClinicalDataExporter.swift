import Foundation
import PDFKit
import CryptoKit

final class ClinicalDataExporter {
    private let errorHandler = XCErrorHandler.shared
    private let performanceMonitor = XCPerformanceMonitor.shared
    private let dataStore = ClinicalDataStore.shared
    
    enum ExportFormat {
        case pdf
        case dicom
        case json
        case encrypted
    }
    
    struct ExportConfiguration {
        let format: ExportFormat
        let includePatientData: Bool
        let includeScanData: Bool
        let includeAnalysis: Bool
        let encryptionRequired: Bool
        let recipientPublicKey: SecKey?
    }
    
    func exportClinicalCase(_ caseId: String, config: ExportConfiguration) throws -> URL {
        performanceMonitor.startMeasuring("DataExport")
        
        do {
            // Validate export permissions
            try validateExportPermissions(for: caseId)
            
            // Retrieve and prepare data
            let clinicalCase = try dataStore.retrieveClinicalCase(caseId)
            let exportData = try prepareExportData(clinicalCase, config: config)
            
            // Generate export file
            let exportURL = try generateExportFile(data: exportData, config: config)
            
            // Create audit log
            createExportAuditLog(caseId: caseId, config: config)
            
            performanceMonitor.stopMeasuring("DataExport")
            return exportURL
            
        } catch {
            performanceMonitor.stopMeasuring("DataExport")
            errorHandler.handle(error, severity: .high)
            throw error
        }
    }
    
    private func validateExportPermissions(for caseId: String) throws {
        // Check user permissions and data access rights
        guard let currentUser = getCurrentUser(),
              currentUser.canExportClinicalData else {
            throw ExportError.insufficientPermissions
        }
        
        // Verify data exists and is accessible
        guard try dataStore.clinicalCaseExists(caseId) else {
            throw ExportError.caseNotFound
        }
    }
    
    private func prepareExportData(_ clinicalCase: ClinicalCase, config: ExportConfiguration) throws -> Data {
        var exportData: [String: Any] = [:]
        
        if config.includePatientData {
            exportData["patient"] = try preparePatientData(clinicalCase.patientInfo)
        }
        
        if config.includeScanData {
            exportData["scans"] = try prepareScanData(clinicalCase.scanData)
        }
        
        if config.includeAnalysis {
            exportData["analysis"] = try prepareAnalysisData(clinicalCase)
        }
        
        return try JSONSerialization.data(withJSONObject: exportData)
    }
    
    private func preparePatientData(_ patientInfo: PatientInfo) throws -> [String: Any] {
        // Remove sensitive information if needed
        return [
            "id": patientInfo.id,
            "age": patientInfo.age,
            "gender": patientInfo.gender,
            "medical_history": patientInfo.medicalHistory
        ]
    }
    
    private func prepareScanData(_ scanData: ScanData) throws -> [String: Any] {
        return [
            "id": scanData.id.uuidString,
            "timestamp": scanData.timestamp.ISO8601Format(),
            "type": scanData.scanType.rawValue,
            "quality_metrics": [
                "point_density": scanData.qualityMetrics.pointDensity,
                "surface_completeness": scanData.qualityMetrics.surfaceCompleteness,
                "noise_level": scanData.qualityMetrics.noiseLevel,
                "feature_preservation": scanData.qualityMetrics.featurePreservation
            ]
        ]
    }
    
    private func prepareAnalysisData(_ clinicalCase: ClinicalCase) throws -> [String: Any] {
        return [
            "treatment_plan": [
                "procedure": clinicalCase.treatmentPlan.recommendedProcedure,
                "graft_count": clinicalCase.treatmentPlan.graftCount,
                "target_density": clinicalCase.treatmentPlan.targetDensity
            ],
            "follow_up": [
                "initial": clinicalCase.followUpSchedule.initialFollowUp.ISO8601Format(),
                "completion": clinicalCase.followUpSchedule.completionDate.ISO8601Format()
            ]
        ]
    }
    
    private func generateExportFile(data: Data, config: ExportConfiguration) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let fileName = "clinical_export_\(Date().timeIntervalSince1970)"
        
        switch config.format {
        case .pdf:
            return try generatePDFExport(data: data, directory: temporaryDirectory, fileName: fileName)
        case .dicom:
            return try generateDICOMExport(data: data, directory: temporaryDirectory, fileName: fileName)
        case .json:
            return try generateJSONExport(data: data, directory: temporaryDirectory, fileName: fileName)
        case .encrypted:
            return try generateEncryptedExport(data: data, config: config, directory: temporaryDirectory, fileName: fileName)
        }
    }
    
    private func generatePDFExport(data: Data, directory: URL, fileName: String) throws -> URL {
        let pdfURL = directory.appendingPathComponent("\(fileName).pdf")
        
        let pdfDocument = PDFDocument()
        
        // Create PDF content
        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let prettyPrintedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: prettyPrintedData, encoding: .utf8) {
            
            let attributedString = NSAttributedString(
                string: jsonString,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.black
                ]
            )
            
            let pdfPage = PDFPage(attributedString: attributedString)
            pdfDocument.insert(pdfPage!, at: 0)
        }
        
        pdfDocument.write(to: pdfURL)
        return pdfURL
    }
    
    private func generateDICOMExport(data: Data, directory: URL, fileName: String) throws -> URL {
        // TODO: Implement DICOM export
        throw ExportError.formatNotSupported
    }
    
    private func generateJSONExport(data: Data, directory: URL, fileName: String) throws -> URL {
        let jsonURL = directory.appendingPathComponent("\(fileName).json")
        try data.write(to: jsonURL)
        return jsonURL
    }
    
    private func generateEncryptedExport(data: Data, config: ExportConfiguration, directory: URL, fileName: String) throws -> URL {
        guard let recipientKey = config.recipientPublicKey else {
            throw ExportError.missingRecipientKey
        }
        
        // Generate a random symmetric key
        let symmetricKey = SymmetricKey(size: .bits256)
        
        // Encrypt the data with the symmetric key
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        
        // Encrypt the symmetric key with recipient's public key
        let encryptedSymmetricKey = try encryptSymmetricKey(symmetricKey, with: recipientKey)
        
        // Combine encrypted data and key
        let exportData = CombinedEncryptedData(
            encryptedData: sealedBox.combined!,
            encryptedKey: encryptedSymmetricKey
        )
        
        let encryptedURL = directory.appendingPathComponent("\(fileName).enc")
        try JSONEncoder().encode(exportData).write(to: encryptedURL)
        
        return encryptedURL
    }
    
    private func createExportAuditLog(caseId: String, config: ExportConfiguration) {
        let auditLog = ExportAuditLog(
            timestamp: Date(),
            caseId: caseId,
            exportFormat: config.format,
            exportedBy: getCurrentUser()?.id ?? "unknown",
            includedData: [
                "patient_data": config.includePatientData,
                "scan_data": config.includeScanData,
                "analysis": config.includeAnalysis
            ]
        )
        
        try? dataStore.storeAuditLog(auditLog)
    }
    
    private func encryptSymmetricKey(_ key: SymmetricKey, with publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let encryptedKey = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            key.withUnsafeBytes { Data($0) } as CFData,
            &error
        ) as Data? else {
            throw error?.takeRetainedValue() ?? ExportError.encryptionFailed
        }
        
        return encryptedKey
    }
}

struct CombinedEncryptedData: Codable {
    let encryptedData: Data
    let encryptedKey: Data
}

struct ExportAuditLog: Codable {
    let timestamp: Date
    let caseId: String
    let exportFormat: ExportFormat
    let exportedBy: String
    let includedData: [String: Bool]
}

enum ExportError: Error {
    case insufficientPermissions
    case caseNotFound
    case formatNotSupported
    case missingRecipientKey
    case encryptionFailed
    case exportFailed
}