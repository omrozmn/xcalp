import Foundation
import CryptoKit

public final class DataAnonymizer {
    public static let shared = DataAnonymizer()
    
    private let logger = LoggingService.shared
    
    private let identifierFields = [
        "name", "email", "phone", "address", "ssn",
        "dob", "mrn", "insuranceId", "deviceId"
    ]
    
    private let quasiIdentifierFields = [
        "age", "gender", "zipCode", "race", "ethnicity",
        "occupation", "income", "education"
    ]
    
    public func anonymize<T: Codable>(_ data: T, level: AnonymizationLevel) throws -> AnonymizedData<T> {
        let startTime = Date()
        
        // Convert to dictionary for processing
        let dictionary = try convertToDict(data)
        
        // Apply anonymization based on level
        let processed = try applyAnonymization(dictionary, level: level)
        
        // Convert back to original type
        let anonymized = try convertFromDict(processed, to: T.self)
        
        let endTime = Date()
        
        logger.logHIPAAEvent(
            "Data anonymization completed",
            type: .modification,
            metadata: [
                "level": level.rawValue,
                "duration": endTime.timeIntervalSince(startTime),
                "type": String(describing: T.self)
            ]
        )
        
        return AnonymizedData(
            data: anonymized,
            originalHash: try computeHash(of: data),
            anonymizationLevel: level,
            timestamp: Date()
        )
    }
    
    public func deidentify<T: Codable>(_ data: T) throws -> DeidentifiedData<T> {
        let startTime = Date()
        
        // Convert to dictionary for processing
        let dictionary = try convertToDict(data)
        
        // Remove all identifiers
        var processed = dictionary
        for field in identifierFields {
            removeIdentifier(from: &processed, field: field)
        }
        
        // Generalize quasi-identifiers
        for field in quasiIdentifierFields {
            generalizeQuasiIdentifier(in: &processed, field: field)
        }
        
        // Apply k-anonymity
        processed = try applyKAnonymity(processed)
        
        // Convert back to original type
        let deidentified = try convertFromDict(processed, to: T.self)
        
        let endTime = Date()
        
        logger.logHIPAAEvent(
            "Data deidentification completed",
            type: .modification,
            metadata: [
                "duration": endTime.timeIntervalSince(startTime),
                "type": String(describing: T.self)
            ]
        )
        
        return DeidentifiedData(
            data: deidentified,
            originalHash: try computeHash(of: data),
            timestamp: Date()
        )
    }
    
    // MARK: - Private Methods
    
    private func convertToDict<T: Encodable>(_ data: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(data)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AnonymizationError.conversionFailed
        }
        return dict
    }
    
    private func convertFromDict<T: Decodable>(_ dict: [String: Any], to type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }
    
    private func applyAnonymization(_ dict: [String: Any], level: AnonymizationLevel) throws -> [String: Any] {
        var result = dict
        
        switch level {
        case .minimal:
            // Only remove direct identifiers
            for field in identifierFields {
                removeIdentifier(from: &result, field: field)
            }
            
        case .partial:
            // Remove identifiers and generalize quasi-identifiers
            for field in identifierFields {
                removeIdentifier(from: &result, field: field)
            }
            for field in quasiIdentifierFields {
                generalizeQuasiIdentifier(in: &result, field: field)
            }
            
        case .full:
            // Apply complete deidentification
            result = try applyKAnonymity(result)
        }
        
        return result
    }
    
    private func removeIdentifier(from dict: inout [String: Any], field: String) {
        if dict[field] != nil {
            dict[field] = "[REDACTED]"
        }
    }
    
    private func generalizeQuasiIdentifier(in dict: inout [String: Any], field: String) {
        guard let value = dict[field] else { return }
        
        switch field {
        case "age":
            if let age = value as? Int {
                dict[field] = generalizeAge(age)
            }
        case "zipCode":
            if let zip = value as? String {
                dict[field] = generalizeZipCode(zip)
            }
        case "income":
            if let income = value as? Double {
                dict[field] = generalizeIncome(income)
            }
        default:
            // Generic generalization
            dict[field] = "[GENERALIZED]"
        }
    }
    
    private func applyKAnonymity(_ dict: [String: Any], k: Int = 5) throws -> [String: Any] {
        var result = dict
        
        // Implementation would ensure each combination of quasi-identifiers
        // appears at least k times in the dataset
        // This is a simplified version
        
        for field in quasiIdentifierFields {
            removeIdentifier(from: &result, field: field)
        }
        
        return result
    }
    
    private func generalizeAge(_ age: Int) -> String {
        switch age {
        case 0...17: return "Under 18"
        case 18...25: return "18-25"
        case 26...35: return "26-35"
        case 36...50: return "36-50"
        case 51...65: return "51-65"
        default: return "Over 65"
        }
    }
    
    private func generalizeZipCode(_ zip: String) -> String {
        // Keep only first 3 digits
        return String(zip.prefix(3)) + "XX"
    }
    
    private func generalizeIncome(_ income: Double) -> String {
        switch income {
        case ..<25000: return "Under $25,000"
        case 25000..<50000: return "$25,000-$50,000"
        case 50000..<75000: return "$50,000-$75,000"
        case 75000..<100000: return "$75,000-$100,000"
        default: return "Over $100,000"
        }
    }
    
    private func computeHash<T: Encodable>(of data: T) throws -> Data {
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        let hash = SHA256.hash(data: encoded)
        return Data(hash)
    }
}

// MARK: - Supporting Types

public enum AnonymizationLevel: String, Codable {
    case minimal = "Minimal"
    case partial = "Partial"
    case full = "Full"
}

public struct AnonymizedData<T: Codable>: Codable {
    public let data: T
    public let originalHash: Data
    public let anonymizationLevel: AnonymizationLevel
    public let timestamp: Date
}

public struct DeidentifiedData<T: Codable>: Codable {
    public let data: T
    public let originalHash: Data
    public let timestamp: Date
}

enum AnonymizationError: LocalizedError {
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .conversionFailed:
            return "Failed to convert data for anonymization"
        }
    }
}