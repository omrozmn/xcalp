import Foundation
import CoreImage
import CoreGraphics
import UIKit

class QRCodeGenerator {
    static let shared = QRCodeGenerator()
    
    private let regionManager = RegionalComplianceManager.shared
    private let localization = LocalizationManager.shared
    
    // Regional QR code configurations
    private var qrConfigs: [Region: QRConfig] = [
        .unitedStates: .init(
            correctionLevel: .high,
            logo: true,
            colorScheme: .standard,
            format: .standard
        ),
        .europeanUnion: .init(
            correctionLevel: .quartile,
            logo: true,
            colorScheme: .standard,
            format: .gdpr
        ),
        .southAsia: .init(
            correctionLevel: .high,
            logo: true,
            colorScheme: .cultural,
            format: .localized
        ),
        .mediterranean: .init(
            correctionLevel: .quartile,
            logo: true,
            colorScheme: .cultural,
            format: .localized
        ),
        .africanDescent: .init(
            correctionLevel: .high,
            logo: true,
            colorScheme: .cultural,
            format: .localized
        )
    ]
    
    private init() {}
    
    // MARK: - Public Interface
    
    func generateQRCode(
        for content: QRContent,
        size: CGSize = CGSize(width: 200, height: 200)
    ) throws -> UIImage {
        let region = regionManager.getCurrentRegion()
        let config = qrConfigs[region] ?? .default
        
        // Add regional metadata
        var processedContent = try addRegionalMetadata(to: content, config: config)
        
        // Add cultural context if needed
        processedContent = try addCulturalContext(to: processedContent, region: region)
        
        // Generate basic QR code
        guard let qrCode = generateBasicQRCode(
            from: processedContent,
            size: size,
            correctionLevel: config.correctionLevel
        ) else {
            throw QRError.generationFailed
        }
        
        // Apply cultural styling
        let styledQR = try applyCulturalStyling(
            qrCode,
            config: config,
            region: region
        )
        
        // Add logo if needed
        if config.logo {
            return try addLogo(to: styledQR, region: region)
        }
        
        return styledQR
    }
    
    func generateBatchQRCodes(
        contents: [QRContent],
        size: CGSize = CGSize(width: 200, height: 200)
    ) async throws -> [UIImage] {
        return try await withThrowingTaskGroup(of: UIImage.self) { group in
            for content in contents {
                group.addTask {
                    return try self.generateQRCode(for: content, size: size)
                }
            }
            
            var results: [UIImage] = []
            for try await result in group {
                results.append(result)
            }
            
            return results
        }
    }
    
    // MARK: - Private Methods
    
    private func addRegionalMetadata(
        to content: QRContent,
        config: QRConfig
    ) throws -> QRContent {
        var processed = content
        processed.metadata["format_version"] = config.format.rawValue
        processed.metadata["region"] = regionManager.getCurrentRegion().rawValue
        processed.metadata["timestamp"] = Date().timeIntervalSince1970
        
        if config.format == .gdpr {
            processed.metadata["data_controller"] = "xcalp.clinic"
            processed.metadata["purpose"] = "medical_records"
            processed.metadata["retention"] = "5_years"
        }
        
        return processed
    }
    
    private func addCulturalContext(
        to content: QRContent,
        region: Region
    ) throws -> QRContent {
        var processed = content
        
        // Add cultural metadata based on region
        switch region {
        case .southAsia, .mediterranean, .africanDescent:
            if let culturalPreferences = try? await SecurePreferencesManager.shared.getCulturalPreferences() {
                processed.metadata["cultural_context"] = culturalPreferences.traditionalStyles.map { $0.rawValue }
                processed.metadata["religious_context"] = culturalPreferences.religionConsiderations.map { String(describing: $0) }
            }
        default:
            break
        }
        
        return processed
    }
    
    private func generateBasicQRCode(
        from content: QRContent,
        size: CGSize,
        correctionLevel: QRCorrectionLevel
    ) -> CIImage? {
        // Convert content to JSON
        guard let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        // Create QR code
        let data = jsonString.data(using: .utf8)
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")
        
        return qrFilter.outputImage?.transformed(by: CGAffineTransform(scaleX: size.width, y: size.height))
    }
    
    private func applyCulturalStyling(
        _ qrCode: CIImage,
        config: QRConfig,
        region: Region
    ) throws -> UIImage {
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(qrCode, from: qrCode.extent) else {
            throw QRError.stylingFailed
        }
        
        let size = cgImage.width
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            throw QRError.stylingFailed
        }
        
        let colors = getColorScheme(config.colorScheme, for: region)
        
        // Apply background
        context.setFillColor(colors.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        
        // Draw QR code with cultural styling
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        context.setFillColor(colors.foreground.cgColor)
        context.draw(cgImage, in: rect)
        
        // Apply cultural patterns if needed
        if config.colorScheme == .cultural {
            try applyRegionalPatterns(context, region: region, size: size)
        }
        
        guard let result = UIGraphicsGetImageFromCurrentImageContext() else {
            throw QRError.stylingFailed
        }
        
        return result
    }
    
    private func addLogo(to qrCode: UIImage, region: Region) throws -> UIImage {
        guard let logo = getRegionalLogo(for: region) else {
            return qrCode
        }
        
        let size = qrCode.size
        let logoSize = CGSize(width: size.width * 0.2, height: size.height * 0.2)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        qrCode.draw(in: CGRect(origin: .zero, size: size))
        
        let logoRect = CGRect(
            x: (size.width - logoSize.width) / 2,
            y: (size.height - logoSize.height) / 2,
            width: logoSize.width,
            height: logoSize.height
        )
        
        logo.draw(in: logoRect)
        
        guard let result = UIGraphicsGetImageFromCurrentImageContext() else {
            throw QRError.logoAdditionFailed
        }
        
        return result
    }
    
    private func getColorScheme(_ scheme: QRColorScheme, for region: Region) -> QRColors {
        switch scheme {
        case .standard:
            return QRColors(
                foreground: .black,
                background: .white
            )
        case .cultural:
            return getCulturalColors(for: region)
        }
    }
    
    private func getCulturalColors(for region: Region) -> QRColors {
        switch region {
        case .southAsia:
            return QRColors(
                foreground: UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1),
                background: UIColor(red: 1.0, green: 0.95, blue: 0.9, alpha: 1)
            )
        case .mediterranean:
            return QRColors(
                foreground: UIColor(red: 0, green: 0.3, blue: 0.6, alpha: 1),
                background: UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1)
            )
        case .africanDescent:
            return QRColors(
                foreground: UIColor(red: 0.4, green: 0.2, blue: 0, alpha: 1),
                background: UIColor(red: 1.0, green: 0.9, blue: 0.8, alpha: 1)
            )
        default:
            return QRColors(foreground: .black, background: .white)
        }
    }
    
    private func applyRegionalPatterns(_ context: CGContext, region: Region, size: CGFloat) throws {
        // Implementation would add region-specific decorative patterns
    }
    
    private func getRegionalLogo(for region: Region) -> UIImage? {
        // Implementation would return region-specific logo
        return nil
    }
}

// MARK: - Supporting Types

struct QRConfig {
    let correctionLevel: QRCorrectionLevel
    let logo: Bool
    let colorScheme: QRColorScheme
    let format: QRFormat
    
    static let `default` = QRConfig(
        correctionLevel: .medium,
        logo: false,
        colorScheme: .standard,
        format: .standard
    )
}

struct QRContent: Codable {
    let type: String
    let data: [String: String]
    var metadata: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case type, data, metadata
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encode(metadata.compactMapValues { $0 as? String }, forKey: .metadata)
    }
}

struct QRColors {
    let foreground: UIColor
    let background: UIColor
}

enum QRCorrectionLevel: String {
    case low = "L"      // 7%
    case medium = "M"   // 15%
    case quartile = "Q" // 25%
    case high = "H"     // 30%
}

enum QRColorScheme {
    case standard
    case cultural
}

enum QRFormat: String {
    case standard
    case gdpr
    case localized
}

enum QRError: LocalizedError {
    case generationFailed
    case stylingFailed
    case logoAdditionFailed
    case invalidContent
    
    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "Failed to generate QR code"
        case .stylingFailed:
            return "Failed to apply cultural styling"
        case .logoAdditionFailed:
            return "Failed to add logo to QR code"
        case .invalidContent:
            return "Invalid QR code content"
        }
    }
}