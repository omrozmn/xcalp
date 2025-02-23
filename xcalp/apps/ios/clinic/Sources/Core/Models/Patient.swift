import Foundation

public struct Patient: Identifiable {
    public let id: String
    public let firstName: String
    public let lastName: String
    public let dateOfBirth: Date
    public let gender: Gender
    
    public var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    public init(
        id: String = UUID().uuidString,
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        gender: Gender
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
    }
}

public enum Gender: String, Codable {
    case male
    case female
    case other
}
