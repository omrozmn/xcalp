import Foundation
import ComposableArchitecture

public struct PatientListFeature: Reducer {
    public struct State: Equatable {
        public var patients: [Patient]
        public var isLoading: Bool
        public var searchQuery: String
        public var errorMessage: String?
        
        public init(
            patients: [Patient] = [],
            isLoading: Bool = false,
            searchQuery: String = "",
            errorMessage: String? = nil
        ) {
            self.patients = patients
            self.isLoading = isLoading
            self.searchQuery = searchQuery
            self.errorMessage = errorMessage
        }
    }
    
    public struct Patient: Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let age: Int
        public let lastVisit: Date
        
        public init(
            id: UUID = UUID(),
            name: String,
            age: Int,
            lastVisit: Date
        ) {
            self.id = id
            self.name = name
            self.age = age
            self.lastVisit = lastVisit
        }
    }
    
    public enum Action: Equatable {
        case loadPatients
        case patientsLoaded([Patient])
        case setSearchQuery(String)
        case setError(String?)
    }
    
    public init() {}
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .loadPatients:
                state.isLoading = true
                state.errorMessage = nil
                return .none
                
            case let .patientsLoaded(patients):
                state.patients = patients
                state.isLoading = false
                return .none
                
            case let .setSearchQuery(query):
                state.searchQuery = query
                return .none
                
            case let .setError(error):
                state.errorMessage = error
                state.isLoading = false
                return .none
            }
        }
    }
}
