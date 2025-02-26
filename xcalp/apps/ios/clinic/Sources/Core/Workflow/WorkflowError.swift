import Foundation

enum WorkflowError: LocalizedError {
    case missingCulturalAssessment
    case missingReligiousConsiderations
    case missingTraditionalStyles
    case missingFamilyPatterns
    case missingHairTextureAnalysis
    case incompatibleWorkflow(region: Region)
    case invalidWorkflowStep(step: WorkflowStep)
    
    var errorDescription: String? {
        switch self {
        case .missingCulturalAssessment:
            return "Cultural assessment is required but not completed"
        case .missingReligiousConsiderations:
            return "Religious considerations documentation is required but not completed"
        case .missingTraditionalStyles:
            return "Traditional styles documentation is required but not completed"
        case .missingFamilyPatterns:
            return "Family pattern documentation is required but not completed"
        case .missingHairTextureAnalysis:
            return "Hair texture analysis is required but not completed"
        case .incompatibleWorkflow(let region):
            return "Workflow configuration is not compatible with region: \(region)"
        case .invalidWorkflowStep(let step):
            return "Invalid workflow step encountered: \(step)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingCulturalAssessment:
            return "Complete the cultural assessment section before proceeding"
        case .missingReligiousConsiderations:
            return "Document religious considerations in the cultural assessment"
        case .missingTraditionalStyles:
            return "Document traditional style preferences in the cultural assessment"
        case .missingFamilyPatterns:
            return "Complete the family pattern analysis section"
        case .missingHairTextureAnalysis:
            return "Perform hair texture analysis before proceeding"
        case .incompatibleWorkflow:
            return "Update workflow configuration for the current region"
        case .invalidWorkflowStep:
            return "Review and correct the workflow configuration"
        }
    }
}