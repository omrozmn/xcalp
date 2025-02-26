import Foundation
import CoreData
import ARKit
import Metal

public actor TestDataGenerator {
    private let secureStorage: SecureStorageService
    private let errorHandler: ErrorHandler
    private let mockDataSet: MockDataSet
    
    init(
        secureStorage: SecureStorageService = .shared,
        errorHandler: ErrorHandler = .shared
    ) {
        self.secureStorage = secureStorage
        self.errorHandler = errorHandler
        self.mockDataSet = MockDataSet()
    }
    
    public func generateTestPatients(count: Int) async throws -> [Patient] {
        return try await withThrowingTaskGroup(of: Patient.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await self.generatePatient()
                }
            }
            
            var patients: [Patient] = []
            for try await patient in group {
                patients.append(patient)
            }
            return patients
        }
    }
    
    public func generateTestScans(count: Int) async throws -> [ScanData] {
        return try await withThrowingTaskGroup(of: ScanData.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await self.generateScan()
                }
            }
            
            var scans: [ScanData] = []
            for try await scan in group {
                scans.append(scan)
            }
            return scans
        }
    }
    
    public func generateTestTreatments(count: Int) async throws -> [Treatment] {
        return try await withThrowingTaskGroup(of: Treatment.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try await self.generateTreatment()
                }
            }
            
            var treatments: [Treatment] = []
            for try await treatment in group {
                treatments.append(treatment)
            }
            return treatments
        }
    }
    
    private func generatePatient() async throws -> Patient {
        try await secureStorage.performSecureOperation {
            let patient = Patient(context: secureStorage.mainContext)
            patient.id = UUID()
            patient.firstName = mockDataSet.randomFirstName()
            patient.lastName = mockDataSet.randomLastName()
            patient.dateOfBirth = mockDataSet.randomDateOfBirth()
            patient.gender = mockDataSet.randomGender()
            patient.email = mockDataSet.randomEmail()
            patient.phone = mockDataSet.randomPhone()
            patient.address = mockDataSet.randomAddress()
            patient.medicalHistory = mockDataSet.randomMedicalHistory()
            patient.createdAt = Date()
            patient.updatedAt = Date()
            return patient
        }
    }
    
    private func generateScan() async throws -> ScanData {
        let vertices = generateMockVertices(count: 1000)
        let normals = generateMockNormals(count: 1000)
        let indices = generateMockIndices(count: 3000)
        
        return ScanData(
            id: UUID(),
            patientId: UUID(),
            timestamp: Date(),
            vertices: vertices,
            normals: normals,
            indices: indices,
            metadata: generateScanMetadata()
        )
    }
    
    private func generateTreatment() async throws -> Treatment {
        try await secureStorage.performSecureOperation {
            let treatment = Treatment(context: secureStorage.mainContext)
            treatment.id = UUID()
            treatment.patientId = UUID()
            treatment.type = mockDataSet.randomTreatmentType()
            treatment.date = mockDataSet.randomFutureDate()
            treatment.notes = mockDataSet.randomTreatmentNotes()
            treatment.status = mockDataSet.randomTreatmentStatus()
            return treatment
        }
    }
    
    private func generateMockVertices(count: Int) -> [SIMD3<Float>] {
        (0..<count).map { _ in
            SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
        }
    }
    
    private func generateMockNormals(count: Int) -> [SIMD3<Float>] {
        (0..<count).map { _ in
            let normal = SIMD3<Float>(
                Float.random(in: -1...1),
                Float.random(in: -1...1),
                Float.random(in: -1...1)
            )
            return normalize(normal)
        }
    }
    
    private func generateMockIndices(count: Int) -> [UInt32] {
        (0..<count).map { _ in
            UInt32.random(in: 0..<1000)
        }
    }
    
    private func generateScanMetadata() -> [String: Any] {
        [
            "scanDuration": TimeInterval.random(in: 30...300),
            "frameCount": Int.random(in: 100...1000),
            "averageProcessingTime": TimeInterval.random(in: 0.01...0.05),
            "meshVertexCount": Int.random(in: 1000...10000),
            "qualityScore": Float.random(in: 0.7...1.0),
            "lightingQuality": Float.random(in: 0.8...1.0),
            "motionQuality": Float.random(in: 0.8...1.0),
            "depthQuality": Float.random(in: 0.8...1.0),
            "performanceIssues": [] as [String]
        ]
    }
}

// MARK: - Supporting Types

private struct MockDataSet {
    private let firstNames = [
        "James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda",
        "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica"
    ]
    
    private let lastNames = [
        "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
        "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson"
    ]
    
    private let treatmentTypes = [
        "Initial Consultation", "Follow-up", "Surgery Planning", "Post-op Check",
        "Evaluation", "Treatment Session", "Final Review"
    ]
    
    private let treatmentStatuses = [
        "Scheduled", "In Progress", "Completed", "Cancelled", "Postponed"
    ]
    
    func randomFirstName() -> String {
        firstNames.randomElement()!
    }
    
    func randomLastName() -> String {
        lastNames.randomElement()!
    }
    
    func randomDateOfBirth() -> Date {
        Calendar.current.date(
            byAdding: .year,
            value: -Int.random(in: 18...80),
            to: Date()
        )!
    }
    
    func randomGender() -> String {
        ["male", "female", "other"].randomElement()!
    }
    
    func randomEmail() -> String {
        let username = "\(randomFirstName().lowercased()).\(randomLastName().lowercased())"
        let domain = ["example.com", "test.com", "mock.com"].randomElement()!
        return "\(username)@\(domain)"
    }
    
    func randomPhone() -> String {
        let areaCode = String(format: "%03d", Int.random(in: 200...999))
        let prefix = String(format: "%03d", Int.random(in: 0...999))
        let lineNumber = String(format: "%04d", Int.random(in: 0...9999))
        return "\(areaCode)-\(prefix)-\(lineNumber)"
    }
    
    func randomAddress() -> String {
        let number = Int.random(in: 100...9999)
        let streets = ["Main St", "Oak Ave", "Maple Dr", "Cedar Ln", "Pine Rd"]
        let cities = ["Springfield", "Rivertown", "Lakeside", "Hillcrest", "Meadowbrook"]
        let states = ["CA", "NY", "TX", "FL", "IL"]
        
        return "\(number) \(streets.randomElement()!), \(cities.randomElement()!), \(states.randomElement()!) \(Int.random(in: 10000...99999))"
    }
    
    func randomMedicalHistory() -> String {
        let conditions = [
            "No significant medical history",
            "Hypertension - controlled with medication",
            "Type 2 Diabetes - diet controlled",
            "Mild asthma - occasional inhaler use",
            "Previous knee surgery (2019)"
        ]
        return conditions.randomElement()!
    }
    
    func randomTreatmentType() -> String {
        treatmentTypes.randomElement()!
    }
    
    func randomTreatmentStatus() -> String {
        treatmentStatuses.randomElement()!
    }
    
    func randomTreatmentNotes() -> String {
        [
            "Patient responding well to treatment plan",
            "Minor adjustments needed to optimize results",
            "Follow-up scheduled in 2 weeks",
            "Treatment progressing as expected",
            "Additional consultation recommended"
        ].randomElement()!
    }
    
    func randomFutureDate() -> Date {
        Calendar.current.date(
            byAdding: .day,
            value: Int.random(in: 1...90),
            to: Date()
        )!
    }
}

public struct ScanData {
    let id: UUID
    let patientId: UUID
    let timestamp: Date
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
    let metadata: [String: Any]
}