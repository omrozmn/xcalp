import Foundation

struct TreatmentTemplate: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String
    let version: Int
    let createdAt: Date
    let updatedAt: Date
    let parameters: [Parameter]
    let regions: [TreatmentRegion]
    let author: String
    let isCustom: Bool
    let parentTemplateId: UUID?
    let versionNotes: String?
    let status: TemplateStatus

    enum TemplateStatus: String, Codable {
        case draft
        case active
        case deprecated
        case archived
    }
    
    struct Parameter: Codable, Identifiable, Equatable {
        let id: UUID
        let name: String
        let type: ParameterType
        let value: String?
        let range: ParameterRange?
        let isRequired: Bool
        let description: String?
        
        enum ParameterType: String, Codable {
            case number
            case text
            case boolean
            case selection
            case measurement
            case density
            case direction
        }
        
        struct ParameterRange: Codable, Equatable {
            let minimum: Double?
            let maximum: Double?
            let step: Double?
            let options: [String]?
            let unit: String?
        }
    }
    
    struct TemplateParameters: Codable, Equatable {
        let targetDensity: Double
        let graftSpacing: Double
        let angleVariation: Double
        let naturalness: Double
        let customParameters: [UUID: Parameter]
        
        var isValid: Bool {
            targetDensity >= 20 && targetDensity <= 60 &&
            graftSpacing >= 0.5 && graftSpacing <= 1.5 &&
            angleVariation >= 0 && angleVariation <= 30 &&
            naturalness >= 0 && naturalness <= 1 &&
            customParameters.values.allSatisfy { $0.isValid }
        }
    }

    var isValid: Bool {
        guard !name.isEmpty,
              !description.isEmpty,
              !regions.isEmpty,
              regions.allSatisfy({ $0.isValid }),
              parameters.allSatisfy({ $0.isValid }) else {
            return false
        }

        // Validate region relationships
        let recipientRegions = regions.filter { $0.type == .recipient }
        let donorRegions = regions.filter { $0.type == .donor }
        
        // Must have at least one recipient and one donor region
        guard !recipientRegions.isEmpty, !donorRegions.isEmpty else {
            return false
        }

        // Validate that regions don't overlap
        for i in 0..<regions.count {
            for j in (i + 1)..<regions.count {
                if regions[i].overlaps(with: regions[j]) {
                    return false
                }
            }
        }

        return true
    }

    func validateCompatibility(with scanData: ScanData) -> Bool {
        // Validate that template regions fit within scan boundaries
        let scanBounds = scanData.bounds
        return regions.allSatisfy { region in
            region.boundaries.allSatisfy { point in
                point.x >= scanBounds.min.x && point.x <= scanBounds.max.x &&
                point.y >= scanBounds.min.y && point.y <= scanBounds.max.y &&
                point.z >= scanBounds.min.z && point.z <= scanBounds.max.z
            }
        }
    }
}

struct TreatmentRegion: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: RegionType
    let boundaries: [Point3D]
    let parameters: RegionParameters
    
    enum RegionType: String, Codable {
        case donor
        case recipient
    }
    
    struct RegionParameters: Codable, Equatable {
        let density: Double
        let direction: Double
        let spacing: Double
        let maximumDeviation: Double
        
        var isValid: Bool {
            density >= 20 && density <= 60 &&
            spacing >= 0.5 && spacing <= 1.5 &&
            maximumDeviation >= 0 && maximumDeviation <= 30
        }
    }
    
    var isValid: Bool {
        !name.isEmpty &&
        !boundaries.isEmpty &&
        boundaries.count >= 3 && // Minimum points for a valid region
        parameters.isValid
    }
}

struct Point3D: Codable, Equatable {
    let x: Double
    let y: Double
    let z: Double
}

struct Direction3D: Codable, Equatable {
    let x: Double
    let y: Double
    let z: Double
    
    var normalized: Direction3D {
        let length = sqrt(x * x + y * y + z * z)
        return Direction3D(
            x: x / length,
            y: y / length,
            z: z / length
        )
    }
}
