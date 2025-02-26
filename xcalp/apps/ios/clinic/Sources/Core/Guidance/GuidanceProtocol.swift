import Foundation
import ARKit
import CoreHaptics

public struct GuidanceProtocol {
    // Clinical workflow phases
    public enum ScanningPhase {
        case preparation    // Environment and device check
        case positioning   // Initial patient/device positioning
        case scanning      // Active scanning phase
        case verification  // Quality verification
        case completion   // Final checks and data validation
    }
    
    // Structured guidance messages
    public struct GuidanceStep {
        let phase: ScanningPhase
        let visualGuide: VisualGuide?
        let voicePrompt: String
        let hapticPattern: HapticPattern
        let qualityThresholds: QualityThresholds
        let autoAdvance: Bool
        let minDuration: Double?
    }
    
    // Quality thresholds for each phase
    public struct QualityThresholds {
        let pointDensity: Float      // points/cm²
        let surfaceCompleteness: Float // percentage
        let featurePreservation: Float // percentage
        let motionStability: Float    // 0-1 scale
        let lightingQuality: Float    // 0-1 scale
        
        static let preparation = QualityThresholds(
            pointDensity: 0,
            surfaceCompleteness: 0,
            featurePreservation: 0,
            motionStability: 0.9,
            lightingQuality: 0.8
        )
        
        static let scanning = QualityThresholds(
            pointDensity: 750,
            surfaceCompleteness: 0.98,
            featurePreservation: 0.95,
            motionStability: 0.8,
            lightingQuality: 0.7
        )
        
        static let verification = QualityThresholds(
            pointDensity: 900,
            surfaceCompleteness: 0.99,
            featurePreservation: 0.98,
            motionStability: 0.9,
            lightingQuality: 0.8
        )
    }
    
    // Clinical workflow definition
    static let clinicalWorkflow: [GuidanceStep] = [
        // Preparation Phase
        GuidanceStep(
            phase: .preparation,
            visualGuide: .environmentCheck,
            voicePrompt: "Please ensure good lighting and clear view of patient's head",
            hapticPattern: .singleTap,
            qualityThresholds: .preparation,
            autoAdvance: true,
            minDuration: nil
        ),
        
        // Positioning Phase
        GuidanceStep(
            phase: .positioning,
            visualGuide: .positioningGuide,
            voicePrompt: "Position device 30-40cm from patient's head",
            hapticPattern: .continuousFeedback,
            qualityThresholds: .preparation,
            autoAdvance: false,
            minDuration: nil
        ),
        
        // Initial Scanning Phase
        GuidanceStep(
            phase: .scanning,
            visualGuide: .scanningPattern,
            voicePrompt: "Begin scanning from the front, moving in a systematic pattern",
            hapticPattern: .dynamicFeedback,
            qualityThresholds: .scanning,
            autoAdvance: false,
            minDuration: nil
        ),
        
        // Detail Scanning Phase
        GuidanceStep(
            phase: .scanning,
            visualGuide: .detailCapture,
            voicePrompt: "Focus on capturing detailed areas",
            hapticPattern: .dynamicFeedback,
            qualityThresholds: .scanning,
            autoAdvance: false,
            minDuration: nil
        ),
        
        // Verification Phase
        GuidanceStep(
            phase: .verification,
            visualGuide: .qualityCheck,
            voicePrompt: "Verifying scan quality",
            hapticPattern: .success,
            qualityThresholds: .verification,
            autoAdvance: true,
            minDuration: nil
        )
    ]
    
    // Enhanced guidance steps for better user experience
    private let enhancedGuidanceSteps: [GuidanceStep] = [
        // Initial Setup Phase
        GuidanceStep(
            phase: .preparation,
            visualGuide: .environmentCheck,
            voicePrompt: "Please ensure good lighting and a clear view. Hold the device at arm's length.",
            hapticPattern: .singleTap,
            qualityThresholds: .preparation,
            autoAdvance: true,
            minDuration: 3.0
        ),
        
        // Positioning Phase
        GuidanceStep(
            phase: .positioning,
            visualGuide: .positioningGuide,
            voicePrompt: "Position device 30-40cm from patient's head. Keep device steady.",
            hapticPattern: .continuousFeedback,
            qualityThresholds: .positioning,
            autoAdvance: false,
            minDuration: 5.0
        ),
        
        // Initial Scanning Phase
        GuidanceStep(
            phase: .scanning,
            visualGuide: .scanningPattern,
            voicePrompt: "Begin scanning from the front. Move slowly in a circular pattern.",
            hapticPattern: .dynamicFeedback,
            qualityThresholds: .scanning,
            autoAdvance: false,
            minDuration: 10.0
        ),
        
        // Detail Scanning Phase
        GuidanceStep(
            phase: .detailCapture,
            visualGuide: .detailFocus,
            voicePrompt: "Now focus on capturing detailed areas. Pay attention to highlighted regions.",
            hapticPattern: .preciseFeedback,
            qualityThresholds: .detail,
            autoAdvance: false,
            minDuration: 8.0
        ),
        
        // Verification Phase
        GuidanceStep(
            phase: .verification,
            visualGuide: .qualityCheck,
            voicePrompt: "Holding position for final quality check.",
            hapticPattern: .success,
            qualityThresholds: .verification,
            autoAdvance: true,
            minDuration: 3.0
        )
    ]
    
    // Quality validation
    static func validateQuality(metrics: ScanQualityMetrics, phase: ScanningPhase) -> Bool {
        let thresholds = getThresholds(for: phase)
        
        return metrics.pointDensity >= thresholds.pointDensity &&
               metrics.surfaceCompleteness >= thresholds.surfaceCompleteness &&
               metrics.featurePreservation >= thresholds.featurePreservation &&
               metrics.motionStability >= thresholds.motionStability &&
               metrics.lightingQuality >= thresholds.lightingQuality
    }
    
    static func getThresholds(for phase: ScanningPhase) -> QualityThresholds {
        switch phase {
        case .preparation, .positioning:
            return .preparation
        case .scanning:
            return .scanning
        case .verification, .completion:
            return .verification
        }
    }
}

extension GuidanceStep {
    var nextPrompt: String? {
        switch phase {
        case .preparation:
            return "Prepare for positioning..."
        case .positioning:
            return "Ready to start scanning..."
        case .scanning:
            return "Moving to detail capture..."
        case .detailCapture:
            return "Preparing for verification..."
        case .verification:
            return "Scan complete!"
        }
    }
    
    var recoveryPrompt: String? {
        switch phase {
        case .preparation:
            return "Please check lighting conditions and try again."
        case .positioning:
            return "Move device closer to the optimal distance."
        case .scanning:
            return "Slow down movement for better quality."
        case .detailCapture:
            return "Stay focused on highlighted areas."
        case .verification:
            return "Hold steady for quality verification."
        }
    }
}

// Visual guidance types
public enum VisualGuide {
    case environmentCheck
    case positioningGuide
    case scanningPattern
    case detailCapture
    case qualityCheck
    case coverageMap
    case qualityHeatmap
}

// Haptic feedback patterns
public enum HapticPattern {
    case singleTap
    case doubleTap
    case success
    case warning
    case error
    case continuousFeedback
    case dynamicFeedback
    case preciseFeedback
}