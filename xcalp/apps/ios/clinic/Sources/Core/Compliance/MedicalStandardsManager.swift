import Foundation

class MedicalStandardsManager {
    static let shared = MedicalStandardsManager()
    
    private var currentRegion: Region
    private let regionManager = RegionalComplianceManager.shared
    
    private var medicalStandards: [Region: Set<MedicalStandard>] = [
        .unitedStates: [
            .init(
                type: .fda,
                requirements: [
                    .scanningAccuracy(minimum: 0.98),
                    .pointDensity(minimum: 1000),
                    .calibrationFrequency(days: 30)
                ]
            )
        ],
        .europeanUnion: [
            .init(
                type: .mdr,
                requirements: [
                    .scanningAccuracy(minimum: 0.985),
                    .pointDensity(minimum: 1200),
                    .calibrationFrequency(days: 14)
                ]
            )
        ],
        .turkey: [
            .init(
                type: .tmmda,
                requirements: [
                    .scanningAccuracy(minimum: 0.98),
                    .pointDensity(minimum: 1000),
                    .calibrationFrequency(days: 30)
                ]
            )
        ],
        .japanKorea: [
            .init(
                type: .pmda,
                requirements: [
                    .scanningAccuracy(minimum: 0.99),
                    .pointDensity(minimum: 1500),
                    .calibrationFrequency(days: 7)
                ]
            )
        ],
        .middleEast: [
            .init(
                type: .sfda,
                requirements: [
                    .scanningAccuracy(minimum: 0.975),
                    .pointDensity(minimum: 1100),
                    .calibrationFrequency(days: 21)
                ]
            )
        ],
        .australia: [
            .init(
                type: .tga,
                requirements: [
                    .scanningAccuracy(minimum: 0.98),
                    .pointDensity(minimum: 1200),
                    .calibrationFrequency(days: 30)
                ]
            )
        ]
    ]
    
    private init() {
        self.currentRegion = regionManager.getCurrentRegion()
        setupRegionChangeObserver()
    }
    
    private func setupRegionChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRegionChange),
            name: .regionDidChange,
            object: nil
        )
    }
    
    @objc private func handleRegionChange(_ notification: Notification) {
        if let region = notification.userInfo?["region"] as? Region {
            currentRegion = region
        }
    }
    
    func validateMedicalStandards(for scan: ScanData) throws {
        guard let standards = medicalStandards[currentRegion] else {
            throw MedicalStandardError.unsupportedRegion(currentRegion)
        }
        
        for standard in standards {
            try validateStandard(standard, for: scan)
        }
    }
    
    private func validateStandard(_ standard: MedicalStandard, for scan: ScanData) throws {
        for requirement in standard.requirements {
            switch requirement {
            case .scanningAccuracy(let minimum):
                guard scan.accuracy >= minimum else {
                    throw MedicalStandardError.accuracyBelowStandard(
                        required: minimum,
                        actual: scan.accuracy
                    )
                }
                
            case .pointDensity(let minimum):
                guard scan.pointDensity >= minimum else {
                    throw MedicalStandardError.densityBelowStandard(
                        required: minimum,
                        actual: scan.pointDensity
                    )
                }
                
            case .calibrationFrequency(let days):
                guard let lastCalibration = scan.lastCalibrationDate else {
                    throw MedicalStandardError.calibrationRequired
                }
                
                let daysSinceCalibration = Calendar.current.dateComponents(
                    [.day],
                    from: lastCalibration,
                    to: Date()
                ).day ?? Int.max
                
                guard daysSinceCalibration <= days else {
                    throw MedicalStandardError.calibrationExpired(
                        daysAgo: daysSinceCalibration
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct MedicalStandard {
    let type: StandardType
    let requirements: Set<Requirement>
    
    enum StandardType {
        case fda    // US FDA
        case mdr    // EU Medical Device Regulation
        case tmmda  // Turkish Medicines and Medical Devices Agency
        case pmda   // Japan PMDA
        case sfda   // Saudi Food and Drug Authority
        case tga    // Australia Therapeutic Goods Administration
    }
    
    enum Requirement: Hashable {
        case scanningAccuracy(minimum: Float)
        case pointDensity(minimum: Int)
        case calibrationFrequency(days: Int)
    }
}

enum MedicalStandardError: LocalizedError {
    case unsupportedRegion(Region)
    case accuracyBelowStandard(required: Float, actual: Float)
    case densityBelowStandard(required: Int, actual: Int)
    case calibrationRequired
    case calibrationExpired(daysAgo: Int)
    
    var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Medical standards not defined for region: \(region)"
        case .accuracyBelowStandard(let required, let actual):
            return "Scan accuracy (\(actual)) below required standard (\(required))"
        case .densityBelowStandard(let required, let actual):
            return "Point density (\(actual)) below required standard (\(required))"
        case .calibrationRequired:
            return "Device calibration required before scanning"
        case .calibrationExpired(let days):
            return "Device calibration expired \(days) days ago"
        }
    }
}