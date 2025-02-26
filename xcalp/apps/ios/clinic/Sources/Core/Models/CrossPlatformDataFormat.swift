import Foundation

// Cross-platform scan data format
struct XCScanData: Codable {
    let metadata: XCMetadata
    let scanPoints: [XCPoint3D]
    let analysis: XCAnalysisData?
    let annotations: [XCAnnotation]
    
    // Convert platform-specific format to cross-platform
    static func fromNative(_ nativeData: ScanData) throws -> XCScanData {
        return XCScanData(
            metadata: .init(
                id: nativeData.id,
                version: AppVersion.current,
                timestamp: Date(),
                platform: "iOS",
                deviceInfo: DeviceInfo.current
            ),
            scanPoints: nativeData.points.map { XCPoint3D(from: $0) },
            analysis: nativeData.analysis.map { XCAnalysisData(from: $0) },
            annotations: nativeData.annotations.map { XCAnnotation(from: $0) }
        )
    }
    
    // Convert cross-platform format to platform-specific
    func toNative() throws -> ScanData {
        return try ScanData(
            id: metadata.id,
            points: scanPoints.map { $0.toNative() },
            analysis: analysis?.toNative(),
            annotations: annotations.map { $0.toNative() }
        )
    }
}

// Standardized 3D point format
struct XCPoint3D: Codable {
    let x: Float
    let y: Float
    let z: Float
    let confidence: Float
    let classification: XCPointClassification
    
    init(from nativePoint: Point3D) {
        self.x = nativePoint.position.x
        self.y = nativePoint.position.y
        self.z = nativePoint.position.z
        self.confidence = nativePoint.confidence
        self.classification = XCPointClassification(from: nativePoint.classification)
    }
    
    func toNative() -> Point3D {
        return Point3D(
            position: SIMD3<Float>(x, y, z),
            confidence: confidence,
            classification: classification.toNative()
        )
    }
}

// Standardized metadata
struct XCMetadata: Codable {
    let id: UUID
    let version: String
    let timestamp: Date
    let platform: String
    let deviceInfo: DeviceInfo
}

// Standardized analysis data
struct XCAnalysisData: Codable {
    let type: String
    let results: [String: AnyCodable]
    let confidence: Float
    let timestamp: Date
    
    static func from(_ native: AnalysisData) -> XCAnalysisData {
        return XCAnalysisData(
            type: native.type.rawValue,
            results: native.results.mapValues { AnyCodable($0) },
            confidence: native.confidence,
            timestamp: native.timestamp
        )
    }
    
    func toNative() throws -> AnalysisData {
        return try AnalysisData(
            type: .init(rawValue: type) ?? .unknown,
            results: results.mapValues { try $0.value() },
            confidence: confidence,
            timestamp: timestamp
        )
    }
}

// Helper for encoding/decoding arbitrary types
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let bool as Bool: try container.encode(bool)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        case let array as [Any]: try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]: try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}