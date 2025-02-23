import Foundation
import CryptoKit

/// Protocol for handling medical data according to HIPAA requirements
public protocol MedicalDataHandler {
    /// Validate data sensitivity level and ensure proper handling
    func validateSensitivity(of data: Data) throws -> SensitivityLevel
    
    /// Apply required protection based on sensitivity
    func applyProtection(to data: Data, level: SensitivityLevel) throws -> Data
    
    /// Process export request with proper audit logging
    func handleExport(of data: Data, for purpose: ExportPurpose) async throws -> Data
    
    /// Verify data integrity and authenticity
    func verifyIntegrity(of data: Data, signature: Data) throws -> Bool
}

/// Handler for medical data operations following HIPAA guidelines
public final class HIPAAMedicalDataHandler: MedicalDataHandler {
    public static let shared = HIPAAMedicalDataHandler()
    
    private let logger = HIPAALogger.shared
    private let keychainManager = KeychainManager.shared
    private let patternCache = NSCache<NSString, NSRegularExpression>()
    
    private init() {}
    
    public func validateSensitivity(of data: Data) throws -> SensitivityLevel {
        // Check for PHI markers
        let containsPHI = try detectPHI(in: data)
        let containsBiometrics = try detectBiometricData(in: data)
        
        switch (containsPHI, containsBiometrics) {
        case (true, true):
            return .critical
        case (true, false):
            return .sensitive
        case (false, true):
            return .confidential
        default:
            return .internal
        }
    }
    
    public func applyProtection(to data: Data, level: SensitivityLevel) throws -> Data {
        let protectedData: Data
        
        switch level {
        case .critical:
            // Double encryption for critical data
            let firstPass = try encrypt(data, keySize: .bits256)
            protectedData = try encrypt(firstPass, keySize: .bits256)
            
        case .sensitive:
            // Strong encryption for sensitive data
            protectedData = try encrypt(data, keySize: .bits256)
            
        case .confidential:
            // Standard encryption for confidential data
            protectedData = try encrypt(data, keySize: .bits128)
            
        case .internal:
            // Basic encryption for internal data
            protectedData = try encrypt(data, keySize: .bits128)
        }
        
        // Generate integrity signature
        let signature = try sign(protectedData)
        
        // Combine protected data and signature
        var result = protectedData
        result.append(signature)
        
        return result
    }
    
    public func handleExport(of data: Data, for purpose: ExportPurpose) async throws -> Data {
        guard let session = SessionManager.shared.currentSession,
              session.user.permissions.contains(.exportData) else {
            throw MedicalDataError.unauthorized
        }
        
        // Log export attempt
        logger.log(
            type: .export,
            action: "Medical Data Export",
            userID: session.user.id,
            details: "Purpose: \(purpose.rawValue)"
        )
        
        let sensitivity = try validateSensitivity(of: data)
        let protectedData = try applyProtection(to: data, level: sensitivity)
        
        // Create export package with metadata
        let exportPackage = ExportPackage(
            data: protectedData,
            metadata: ExportMetadata(
                timestamp: Date(),
                purpose: purpose,
                sensitivity: sensitivity,
                exportedBy: session.user.id
            )
        )
        
        return try JSONEncoder().encode(exportPackage)
    }
    
    public func verifyIntegrity(of data: Data, signature: Data) throws -> Bool {
        // Verify cryptographic signature
        return try verify(data: data, signature: signature)
    }
    
    // MARK: - Private Methods
    
    private func detectPHI(in data: Data) throws -> Bool {
        // Check for common PHI patterns (names, dates, IDs)
        let patterns = try NSRegularExpression.phi
        let range = NSRange(location: 0, length: data.count)
        
        if let string = String(data: data, encoding: .utf8) {
            return patterns.firstMatch(in: string, range: range) != nil
        }
        
        return false
    }
    
    private func detectBiometricData(in data: Data) throws -> Bool {
        // Check file signatures for common biometric formats
        let biometricHeaders: Set<[UInt8]> = [
            [0x00, 0x00, 0x46, 0x4D], // ANSI/NIST-ITL fingerprint
            [0x46, 0x41, 0x52, 0x00], // Facial recognition
            [0x49, 0x52, 0x49, 0x53]  // Iris scan
        ]
        
        let header = Array(data.prefix(4))
        return biometricHeaders.contains(header)
    }
    
    private func encrypt(_ data: Data, keySize: SymmetricKeySize) throws -> Data {
        let key = SymmetricKey(size: keySize)
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw MedicalDataError.protectionFailed
        }
        return combined
    }
    
    private func sign(_ data: Data) throws -> Data {
        let signature = try HMAC<SHA256>.authenticationCode(
            for: data,
            using: SymmetricKey(size: .bits256)
        )
        return Data(signature)
    }
    
    private func verify(data: Data, signature: Data) throws -> Bool {
        let computedSignature = try sign(data)
        return computedSignature == signature
    }
    
    public func validateAndSanitize(_ data: Data) throws -> Data {
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw HIPAAError.invalidData
        }
        
        // Remove any PII using regex patterns
        var sanitizedString = jsonString
        for pattern in PrivacyPatterns.allCases {
            let regex = try getCachedRegex(for: pattern)
            sanitizedString = regex.stringByReplacingMatches(
                in: sanitizedString,
                range: NSRange(sanitizedString.startIndex..., in: sanitizedString),
                withTemplate: "[REDACTED]"
            )
        }
        
        guard let sanitizedData = sanitizedString.data(using: .utf8) else {
            throw HIPAAError.sanitizationFailed
        }
        
        return sanitizedData
    }
    
    private func getCachedRegex(for pattern: PrivacyPatterns) throws -> NSRegularExpression {
        if let cached = patternCache.object(forKey: pattern.rawValue as NSString) {
            return cached
        }
        
        do {
            let regex = try NSRegularExpression(pattern: pattern.rawValue)
            patternCache.setObject(regex, forKey: pattern.rawValue as NSString)
            return regex
        } catch {
            throw HIPAAError.invalidPattern(error)
        }
    }
    
    private func verifyDataIntegrity(_ data: Data) throws -> Bool {
        // Split data into content and signature
        guard data.count >= 32 else { return false }
        let contentData = data.dropLast(32)
        let signature = data.suffix(32)
        
        // Verify HMAC signature
        let computedSignature = try sign(contentData)
        guard signature.count == computedSignature.count else { return false }
        
        // Use constant-time comparison to prevent timing attacks
        return computedSignature.withUnsafeBytes { computedPtr in
            signature.withUnsafeBytes { signaturePtr in
                if computedPtr.count != signaturePtr.count { return false }
                var result: UInt8 = 0
                for i in 0..<computedPtr.count {
                    result |= computedPtr[i] ^ signaturePtr[i]
                }
                return result == 0
            }
        }
    }
    
    public func verifyAndValidateExport(_ exportedData: Data) throws -> Bool {
        let package = try JSONDecoder().decode(ExportPackage.self, from: exportedData)
        
        // Verify data integrity
        guard try verifyDataIntegrity(package.data) else {
            throw MedicalDataError.integrityCheckFailed
        }
        
        // Validate metadata
        let metadata = package.metadata
        guard metadata.timestamp <= Date() else {
            throw MedicalDataError.invalidData
        }
        
        // Log validation
        logger.log(
            type: .security,
            action: "Export Validation",
            userID: metadata.exportedBy,
            details: "Purpose: \(metadata.purpose.rawValue), Sensitivity: \(metadata.sensitivity.rawValue)"
        )
        
        return true
    }
}

// MARK: - Supporting Types

extension HIPAAMedicalDataHandler {
    public enum SensitivityLevel: String, Codable {
        case critical    // PHI + Biometric data
        case sensitive   // PHI only
        case confidential // Biometric data only
        case internal    // Other medical data
    }
    
    public enum ExportPurpose: String, Codable {
        case patientRequest = "PATIENT_REQUEST"
        case referral = "REFERRAL"
        case research = "RESEARCH"
        case legal = "LEGAL"
        case audit = "AUDIT"
    }
    
    public struct ExportMetadata: Codable {
        let timestamp: Date
        let purpose: ExportPurpose
        let sensitivity: SensitivityLevel
        let exportedBy: String
    }
    
    public struct ExportPackage: Codable {
        let data: Data
        let metadata: ExportMetadata
    }
    
    public enum MedicalDataError: LocalizedError {
        case unauthorized
        case invalidData
        case protectionFailed
        case integrityCheckFailed
        
        public var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Unauthorized access to medical data"
            case .invalidData:
                return "Invalid or corrupted medical data"
            case .protectionFailed:
                return "Failed to apply required protection"
            case .integrityCheckFailed:
                return "Data integrity check failed"
            }
        }
    }
    
    public enum HIPAAError: LocalizedError {
        case invalidData
        case sanitizationFailed
        case invalidPattern(Error)
        
        public var errorDescription: String? {
            switch self {
            case .invalidData:
                return "Invalid data format"
            case .sanitizationFailed:
                return "Failed to sanitize data"
            case .invalidPattern(let error):
                return "Invalid regex pattern: \(error.localizedDescription)"
            }
        }
    }
    
    public enum PrivacyPatterns: String, CaseIterable {
        case ssn = "\\d{3}-\\d{2}-\\d{4}"
        case email = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        case phoneNumber = "\\(\\d{3}\\)\\s?\\d{3}-\\d{4}"
        case creditCard = "\\d{4}[- ]\\d{4}[- ]\\d{4}[- ]\\d{4}"
    }
}

// MARK: - NSRegularExpression Extension

private extension NSRegularExpression {
    static let phi: NSRegularExpression = {
        // Common PHI patterns (simplified for example)
        let patterns = [
            "\\b\\d{3}-\\d{2}-\\d{4}\\b",           // SSN
            "\\b\\d{2}/\\d{2}/\\d{4}\\b",           // Dates
            "\\b[A-Za-z]+\\s[A-Za-z]+\\b",          // Names
            "\\b\\d{10}\\b",                        // Phone numbers
            "\\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}\\b" // Email
        ]
        
        let pattern = patterns.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern)
    }()
}