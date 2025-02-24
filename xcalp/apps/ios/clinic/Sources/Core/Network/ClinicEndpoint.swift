import Foundation

public enum ClinicEndpoint: APIEndpoint {
    case getScanHistory(patientId: String)
    case uploadScan(patientId: String, scanData: Data)
    case getTreatmentPlan(planId: String)
    case saveTreatmentPlan(patientId: String, planData: [String: Any])
    case getPatientProfile(patientId: String)
    case updatePatientProfile(patientId: String, profileData: [String: Any])
    
    public var baseURL: String {
        #if DEBUG
        return "https://api.staging.xcalp.com/v1"
        #else
        return "https://api.xcalp.com/v1"
        #endif
    }
    
    public var path: String {
        switch self {
        case .getScanHistory(let patientId):
            return "/patients/\(patientId)/scans"
        case .uploadScan(let patientId, _):
            return "/patients/\(patientId)/scans"
        case .getTreatmentPlan(let planId):
            return "/treatment-plans/\(planId)"
        case .saveTreatmentPlan(let patientId, _):
            return "/patients/\(patientId)/treatment-plans"
        case .getPatientProfile(let patientId):
            return "/patients/\(patientId)"
        case .updatePatientProfile(let patientId, _):
            return "/patients/\(patientId)"
        }
    }
    
    public var method: HTTPMethod {
        switch self {
        case .getScanHistory, .getTreatmentPlan, .getPatientProfile:
            return .get
        case .uploadScan, .saveTreatmentPlan:
            return .post
        case .updatePatientProfile:
            return .put
        }
    }
    
    public var body: [String: Any]? {
        switch self {
        case .getScanHistory, .getTreatmentPlan, .getPatientProfile:
            return nil
        case .uploadScan(_, let scanData):
            return [
                "data": scanData.base64EncodedString(),
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "format": "usdz"
            ]
        case .saveTreatmentPlan(_, let planData):
            return planData
        case .updatePatientProfile(_, let profileData):
            return profileData
        }
    }
    
    public var url: URL? {
        URL(string: baseURL + path)
    }
}
