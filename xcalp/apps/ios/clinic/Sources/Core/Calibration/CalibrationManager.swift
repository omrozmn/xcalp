import Foundation
import ARKit
import CoreMotion

class CalibrationManager {
    static let shared = CalibrationManager()
    private let medicalStandards = MedicalStandardsManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    private let motionManager = CMMotionManager()
    
    private var lastCalibrationDate: Date?
    private var calibrationState: CalibrationState = .uncalibrated
    private var activeCalibration: CalibrationSession?
    private var calibrationObservers: [CalibrationObserver] = []
    
    private init() {
        setupMotionManager()
    }
    
    // MARK: - Public Interface
    
    func startCalibration() async throws -> CalibrationSession {
        performanceMonitor.startMeasuring("calibration_session")
        
        guard !isCalibrating else {
            throw CalibrationError.calibrationInProgress
        }
        
        let session = CalibrationSession(
            id: UUID(),
            startTime: Date(),
            region: RegionalComplianceManager.shared.getCurrentRegion()
        )
        
        activeCalibration = session
        calibrationState = .inProgress
        notifyObservers()
        
        return session
    }
    
    func completeCalibration(_ session: CalibrationSession, with results: CalibrationResults) async throws {
        guard activeCalibration?.id == session.id else {
            throw CalibrationError.invalidSession
        }
        
        try validateCalibrationResults(results)
        
        lastCalibrationDate = Date()
        calibrationState = .calibrated
        activeCalibration = nil
        
        // Store calibration data
        try await storeCalibrationData(session, results: results)
        
        performanceMonitor.stopMeasuring("calibration_session")
        notifyObservers()
    }
    
    func cancelCalibration() {
        activeCalibration = nil
        calibrationState = .uncalibrated
        notifyObservers()
    }
    
    func isCalibrationRequired() -> Bool {
        guard let lastCalibration = lastCalibrationDate else {
            return true
        }
        
        let region = RegionalComplianceManager.shared.getCurrentRegion()
        let standards = medicalStandards.medicalStandards[region] ?? []
        
        // Find the most stringent calibration requirement
        let requiredFrequency = standards.compactMap { standard in
            standard.requirements.compactMap { requirement in
                if case .calibrationFrequency(let days) = requirement {
                    return days
                }
                return nil
            }.min()
        }.min() ?? 30 // Default to 30 days if no specific requirement
        
        let daysSinceCalibration = Calendar.current.dateComponents(
            [.day],
            from: lastCalibration,
            to: Date()
        ).day ?? Int.max
        
        return daysSinceCalibration >= requiredFrequency
    }
    
    func addObserver(_ observer: CalibrationObserver) {
        calibrationObservers.append(observer)
    }
    
    func removeObserver(_ observer: CalibrationObserver) {
        calibrationObservers.removeAll { $0 === observer }
    }
    
    // MARK: - Private Methods
    
    private func setupMotionManager() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
    }
    
    private func validateCalibrationResults(_ results: CalibrationResults) throws {
        guard results.accuracy >= 0.98 else {
            throw CalibrationError.accuracyBelowThreshold(results.accuracy)
        }
        
        guard results.stability >= 0.95 else {
            throw CalibrationError.insufficientStability(results.stability)
        }
        
        guard results.coverage >= 0.90 else {
            throw CalibrationError.insufficientCoverage(results.coverage)
        }
    }
    
    private func storeCalibrationData(_ session: CalibrationSession, results: CalibrationResults) async throws {
        let calibrationData = CalibrationData(
            session: session,
            results: results,
            timestamp: Date()
        )
        
        try await SecureStorage.shared.store(
            calibrationData,
            forKey: "calibration_\(session.id.uuidString)",
            expires: .days(90)
        )
    }
    
    private func notifyObservers() {
        calibrationObservers.forEach { observer in
            observer.calibrationStateChanged(to: calibrationState)
        }
    }
    
    private var isCalibrating: Bool {
        calibrationState == .inProgress
    }
}

// MARK: - Supporting Types

protocol CalibrationObserver: AnyObject {
    func calibrationStateChanged(to state: CalibrationState)
}

enum CalibrationState {
    case uncalibrated
    case inProgress
    case calibrated
}

struct CalibrationSession {
    let id: UUID
    let startTime: Date
    let region: Region
    var checkpoints: [CalibrationCheckpoint] = []
}

struct CalibrationCheckpoint {
    let timestamp: Date
    let motionData: CMDeviceMotion
    let lightingConditions: Float
    let surfaceCharacteristics: SurfaceCharacteristics
}

struct CalibrationResults {
    let accuracy: Float
    let stability: Float
    let coverage: Float
    let environmentalFactors: EnvironmentalFactors
}

struct SurfaceCharacteristics {
    let reflectivity: Float
    let texture: Float
    let uniformity: Float
}

struct EnvironmentalFactors {
    let lightingLevel: Float
    let temperatureCelsius: Float
    let humidity: Float
}

struct CalibrationData: Codable {
    let session: CalibrationSession
    let results: CalibrationResults
    let timestamp: Date
}

enum CalibrationError: LocalizedError {
    case calibrationInProgress
    case invalidSession
    case accuracyBelowThreshold(Float)
    case insufficientStability(Float)
    case insufficientCoverage(Float)
    case environmentalConditions(String)
    
    var errorDescription: String? {
        switch self {
        case .calibrationInProgress:
            return "A calibration session is already in progress"
        case .invalidSession:
            return "Invalid calibration session"
        case .accuracyBelowThreshold(let accuracy):
            return "Calibration accuracy (\(accuracy)) below required threshold"
        case .insufficientStability(let stability):
            return "Calibration stability (\(stability)) below required threshold"
        case .insufficientCoverage(let coverage):
            return "Calibration coverage (\(coverage)) below required threshold"
        case .environmentalConditions(let reason):
            return "Environmental conditions unsuitable: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accuracyBelowThreshold:
            return "Try recalibrating in better lighting conditions"
        case .insufficientStability:
            return "Hold the device more steady during calibration"
        case .insufficientCoverage:
            return "Ensure you cover all required angles during calibration"
        case .environmentalConditions:
            return "Move to an environment with better conditions and try again"
        default:
            return nil
        }
    }
}