import Foundation

protocol APIClient {
    func syncTemplate(_ template: TreatmentTemplate) async throws -> TreatmentTemplate
    func deleteTemplate(_ id: UUID) async throws
}

final class APIClientImpl: APIClient {
    static let shared = APIClientImpl()
    private let baseURL = URL(string: "https://api.xcalp.com/v1")!
    private let session: URLSession
    private let logger = XcalpLogger.shared
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }
    
    func syncTemplate(_ template: TreatmentTemplate) async throws -> TreatmentTemplate {
        let url = baseURL.appendingPathComponent("templates")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(template)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestFailed(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TreatmentTemplate.self, from: data)
    }
    
    func deleteTemplate(_ id: UUID) async throws {
        let url = baseURL.appendingPathComponent("templates/\(id.uuidString)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestFailed(httpResponse.statusCode)
        }
    }
}

enum APIError: LocalizedError {
    case invalidResponse
    case requestFailed(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response"
        case .requestFailed(let statusCode):
            return "Request failed with status code: \(statusCode)"
        }
    }
}