extension PHIDataCheck {
    func validate<T: HIPAACompliant>(_ data: T) async throws {
        // Validate required PHI fields
        guard !data.phi.isEmpty else {
            throw ComplianceError.missingPHI
        }
        
        // Check for sensitive identifiers
        let sensitiveFields = data.phi.keys.filter { isFieldSensitive($0) }
        for field in sensitiveFields {
            guard let value = data.phi[field] else { continue }
            
            // Validate field format
            try validateFieldFormat(field: field, value: value)
            
            // Check for proper encryption
            if let stringValue = value as? String {
                guard stringValue.hasPrefix("encrypted:") else {
                    throw ComplianceError.unencryptedPHI(field: field)
                }
            }
        }
        
        // Validate access controls
        guard data.accessControl != .public else {
            throw ComplianceError.invalidAccessControl
        }
        
        // Verify modification timestamp
        guard data.lastModified <= Date() else {
            throw ComplianceError.invalidTimestamp
        }
        
        LoggingService.shared.logHIPAAEvent(
            "PHI validation successful",
            type: .access,
            metadata: [
                "identifier": data.identifier,
                "dataType": T.dataType.rawValue,
                "fieldsChecked": sensitiveFields
            ]
        )
    }
    
    private func isFieldSensitive(_ field: String) -> Bool {
        let sensitiveFields = [
            "name", "dob", "ssn", "email", "phone",
            "address", "medicalRecordNumber", "insuranceId",
            "diagnosis", "treatment", "medication"
        ]
        return sensitiveFields.contains(field.lowercased())
    }
    
    private func validateFieldFormat(field: String, value: Any) throws {
        switch field.lowercased() {
        case "ssn":
            guard let ssn = value as? String,
                  ssn.range(of: #"^\d{3}-\d{2}-\d{4}$"#, options: .regularExpression) != nil else {
                throw ComplianceError.invalidFieldFormat(field: field)
            }
        case "email":
            guard let email = value as? String,
                  email.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil else {
                throw ComplianceError.invalidFieldFormat(field: field)
            }
        case "phone":
            guard let phone = value as? String,
                  phone.range(of: #"^\d{3}-\d{3}-\d{4}$"#, options: .regularExpression) != nil else {
                throw ComplianceError.invalidFieldFormat(field: field)
            }
        default:
            break
        }
    }
}

enum ComplianceError: LocalizedError {
    case missingPHI
    case unencryptedPHI(field: String)
    case invalidAccessControl
    case invalidTimestamp
    case invalidFieldFormat(field: String)
    
    var errorDescription: String? {
        switch self {
        case .missingPHI:
            return "Missing required PHI data"
        case .unencryptedPHI(let field):
            return "Unencrypted PHI found in field: \(field)"
        case .invalidAccessControl:
            return "Invalid access control level for PHI data"
        case .invalidTimestamp:
            return "Invalid modification timestamp"
        case .invalidFieldFormat(let field):
            return "Invalid format for field: \(field)"
        }
    }
}