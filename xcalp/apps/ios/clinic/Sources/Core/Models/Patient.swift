import Foundation

public struct Patient: Identifiable, Codable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let dateOfBirth: Date
    public let gender: Gender
    public let email: String?
    public let phone: String?
    public let photo: Data?
    public let notes: String?
    public let lastVisit: Date?
    public var scans: [Scan]?
    public var treatments: [Treatment]?
    
    public var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    public var age: Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
    }
    
    public init(
        id: String = UUID().uuidString,
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        gender: Gender,
        email: String? = nil,
        phone: String? = nil,
        photo: Data? = nil,
        notes: String? = nil,
        lastVisit: Date? = nil,
        scans: [Scan]? = nil,
        treatments: [Treatment]? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.email = email
        self.phone = phone
        self.photo = photo
        self.notes = notes
        self.lastVisit = lastVisit
        self.scans = scans
        self.treatments = treatments
    }
}

public enum Gender: String, Codable {
    case male
    case female
    case other
}

public struct Scan: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let quality: Float
    public let notes: String?
}

public struct Treatment: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let type: TreatmentType
    public let status: TreatmentStatus
}

public enum TreatmentType: String, Codable {
    case analysis
    case planning
    case procedure
    case followUp
}

public enum TreatmentStatus: String, Codable {
    case scheduled
    case inProgress
    case completed
    case cancelled
}
