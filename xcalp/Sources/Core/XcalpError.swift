import Foundation

enum XcalpError: Error {
    case networkError(String)
    case dataError(String)
    case unknownError(String)
    
    var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Network Error: \(message)"
        case .dataError(let message):
            return "Data Error: \(message)"
        case .unknownError(let message):
            return "Unknown Error: \(message)"
        }
    }
}
