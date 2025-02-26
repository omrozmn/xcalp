import Foundation

class VersionControlManager {
    private let minimumCompatibleVersion = "1.0.0"
    private var platformVersions: [Platform: String] = [:]
    
    enum Platform: String {
        case ios = "iOS"
        case android = "Android"
        case web = "Web"
        case macos = "macOS"
        case windows = "Windows"
    }
    
    func registerPlatformVersion(_ version: String, for platform: Platform) {
        platformVersions[platform] = version
    }
    
    func checkCompatibility(data: XCScanData) -> CompatibilityResult {
        let dataVersion = Version(string: data.metadata.version)
        let currentVersion = Version(string: AppVersion.current)
        let minVersion = Version(string: minimumCompatibleVersion)
        
        guard let dataV = dataVersion,
              let currentV = currentVersion,
              let minV = minVersion else {
            return .incompatible(reason: "Invalid version format")
        }
        
        // Check minimum version requirement
        if dataV < minV {
            return .incompatible(reason: "Data version too old")
        }
        
        // Check if current version can handle this data
        if dataV > currentV {
            return .needsUpdate(minVersion: data.metadata.version)
        }
        
        // Check for breaking changes
        if dataV.major != currentV.major {
            return .incompatible(reason: "Major version mismatch")
        }
        
        return .compatible
    }
    
    func getCompatibilityMatrix() -> [Platform: VersionRange] {
        return [
            .ios: VersionRange(min: minimumCompatibleVersion, max: AppVersion.current),
            .android: VersionRange(min: "1.0.0", max: platformVersions[.android] ?? "1.0.0"),
            .web: VersionRange(min: "1.0.0", max: platformVersions[.web] ?? "1.0.0"),
            .macos: VersionRange(min: "1.0.0", max: platformVersions[.macos] ?? "1.0.0"),
            .windows: VersionRange(min: "1.0.0", max: platformVersions[.windows] ?? "1.0.0")
        ]
    }
}

struct Version: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    
    init?(string: String) {
        let components = string.split(separator: ".")
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]) else {
            return nil
        }
        
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct VersionRange {
    let min: String
    let max: String
}

enum CompatibilityResult {
    case compatible
    case needsUpdate(minVersion: String)
    case incompatible(reason: String)
}