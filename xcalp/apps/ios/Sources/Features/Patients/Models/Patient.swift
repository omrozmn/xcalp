import Foundation

struct Patient: Codable, Identifiable {
    let id: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var gender: Gender
    var email: String?
    var phone: String?
    var notes: String?
    var lastVisitDate: Date?
    var nextAppointmentDate: Date?
    var profilePhotoUrl: URL?
    var medicalHistory: [MedicalHistoryItem]
    var scans: [String] // Scan IDs
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

enum Gender: String, Codable {
    case male
    case female
    case other
    case preferNotToSay
}

struct MedicalHistoryItem: Codable {
    let id: String
    let date: Date
    let title: String
    let description: String
    let type: MedicalHistoryType
    let attachments: [Attachment]
}

enum MedicalHistoryType: String, Codable {
    case condition
    case medication
    case surgery
    case allergy
    case other
}

struct Attachment: Codable {
    let id: String
    let url: URL
    let type: AttachmentType
    let name: String
    let size: Int64
    let createdAt: Date
}

enum AttachmentType: String, Codable {
    case image
    case document
    case scan
    case other
}