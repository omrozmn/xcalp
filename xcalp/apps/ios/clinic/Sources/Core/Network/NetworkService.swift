import Combine
import Foundation

public final class NetworkService {
    private let networkManager: NetworkManager
    private var cancellables = Set<AnyCancellable>()
    
    public init(networkManager: NetworkManager = .shared) {
        self.networkManager = networkManager
    }
    
    // MARK: - Scan Operations
    
    public func getScanHistory(for patientId: String) async throws -> [ScanRecord] {
        try await networkManager.request(ClinicEndpoint.getScanHistory(patientId: patientId))
    }
    
    public func uploadScan(_ scanData: Data, for patientId: String) async throws -> ScanRecord {
        try await networkManager.request(ClinicEndpoint.uploadScan(patientId: patientId, scanData: scanData))
    }
    
    // MARK: - Treatment Plan Operations
    
    public func getTreatmentPlan(id: String) async throws -> TreatmentPlan {
        try await networkManager.request(ClinicEndpoint.getTreatmentPlan(planId: id))
    }
    
    public func saveTreatmentPlan(_ plan: TreatmentPlan, for patientId: String) async throws -> TreatmentPlan {
        let planData = try plan.asDictionary()
        return try await networkManager.request(ClinicEndpoint.saveTreatmentPlan(patientId: patientId, planData: planData))
    }
    
    // MARK: - Patient Profile Operations
    
    public func getPatientProfile(id: String) async throws -> PatientProfile {
        try await networkManager.request(ClinicEndpoint.getPatientProfile(patientId: id))
    }
    
    public func updatePatientProfile(_ profile: PatientProfile) async throws -> PatientProfile {
        let profileData = try profile.asDictionary()
        return try await networkManager.request(ClinicEndpoint.updatePatientProfile(patientId: profile.id, profileData: profileData))
    }
}

// MARK: - Helper Extensions

private extension Encodable {
    func asDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.decodingError
        }
        return dictionary
    }
}

// MARK: - Model Types

public struct ScanRecord: Codable {
    public let id: String
    public let patientId: String
    public let timestamp: Date
    public let url: URL
    public let format: String
    public let quality: ScanQuality
    
    public struct ScanQuality: Codable {
        public let score: Float
        public let confidence: Float
        public let coverage: Float
    }
}

public struct TreatmentPlan: Codable {
    public let id: String
    public let patientId: String
    public let createdAt: Date
    public let updatedAt: Date
    public let status: Status
    public let grafts: GraftPlan
    public let analysis: AnalysisResults
    
    public enum Status: String, Codable {
        case draft
        case inProgress
        case completed
        case archived
    }
    
    public struct GraftPlan: Codable {
        public let totalCount: Int
        public let density: Float
        public let coverage: Float
        public let regions: [Region]
        
        public struct Region: Codable {
            public let id: String
            public let area: Float
            public let graftCount: Int
            public let density: Float
        }
    }
    
    public struct AnalysisResults: Codable {
        public let hairlineQuality: Float
        public let densityDistribution: Float
        public let growthProjection: Float
        public let recommendations: [String]
    }
}

public struct PatientProfile: Codable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let dateOfBirth: Date
    public let gender: Gender
    public let medicalHistory: MedicalHistory
    public let contactInfo: ContactInfo
    
    public enum Gender: String, Codable {
        case male
        case female
        case other
        case preferNotToSay
    }
    
    public struct MedicalHistory: Codable {
        public let conditions: [String]
        public let medications: [String]
        public let allergies: [String]
        public let previousTreatments: [String]
    }
    
    public struct ContactInfo: Codable {
        public let email: String
        public let phone: String
        public let address: Address
        
        public struct Address: Codable {
            public let street: String
            public let city: String
            public let state: String
            public let country: String
            public let postalCode: String
        }
    }
}
