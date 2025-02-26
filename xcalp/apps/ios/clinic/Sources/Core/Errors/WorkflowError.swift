import Foundation

enum WorkflowError: LocalizedError {
    // Consent Errors
    case missingConsent(ConsentType)
    case expiredConsent(ConsentType)
    case invalidConsent(ConsentType, String)
    
    // Medical History Errors
    case missingMedicalHistory
    case missingMedicalHistoryField(String)
    case outdatedMedicalHistory
    case invalidMedicalRecord(String)
    
    // Photo Errors
    case missingPreoperativePhotos
    case missingPhotoAngle(Int)
    case photoQualityBelowThreshold(angle: Int)
    case photoMetadataMissing(String)
    
    // Scan Errors
    case missingScan
    case scanNotCalibrated
    case insufficientLighting
    case scanQualityBelowThreshold
    case missingTextureAnalysis
    case scanProcessingFailed(String)
    
    // Planning Documentation Errors
    case missingPlanningDocs
    case missingDonorAreaAnalysis
    case missingRecipientAreaAnalysis
    case missingGraftCount
    case missingFutureProjections
    case missingCulturalPreferences
    case missingTextureConsiderations
    case invalidPlanningData(String)
    
    // Post-operative Instruction Errors
    case missingPostOpInstructions
    case missingDefaultLanguageInstructions
    case insufficientLanguageSupport
    case outdatedInstructions
    case invalidInstructionFormat(String)
    
    // Cultural Assessment Errors
    case missingCulturalAssessment
    case missingReligiousConsiderations
    case missingTraditionalStyles
    case missingFamilyPatterns
    case missingHairTextureAnalysis
    case culturalAssessmentIncomplete(String)
    
    var errorDescription: String? {
        switch self {
        // Consent Errors
        case .missingConsent(let type):
            return "Missing required consent: \(type)"
        case .expiredConsent(let type):
            return "Consent has expired: \(type)"
        case .invalidConsent(let type, let reason):
            return "Invalid consent for \(type): \(reason)"
            
        // Medical History Errors
        case .missingMedicalHistory:
            return "Medical history is required"
        case .missingMedicalHistoryField(let field):
            return "Required medical history field missing: \(field)"
        case .outdatedMedicalHistory:
            return "Medical history needs to be updated"
        case .invalidMedicalRecord(let reason):
            return "Invalid medical record: \(reason)"
            
        // Photo Errors
        case .missingPreoperativePhotos:
            return "Pre-operative photos are required"
        case .missingPhotoAngle(let angle):
            return "Required photo angle missing: \(angle)°"
        case .photoQualityBelowThreshold(let angle):
            return "Photo quality below threshold for angle: \(angle)°"
        case .photoMetadataMissing(let metadata):
            return "Photo metadata missing: \(metadata)"
            
        // Scan Errors
        case .missingScan:
            return "3D scan is required"
        case .scanNotCalibrated:
            return "Device needs to be calibrated before scanning"
        case .insufficientLighting:
            return "Lighting conditions are insufficient for scanning"
        case .scanQualityBelowThreshold:
            return "Scan quality is below required threshold"
        case .missingTextureAnalysis:
            return "Texture analysis is required"
        case .scanProcessingFailed(let reason):
            return "Scan processing failed: \(reason)"
            
        // Planning Documentation Errors
        case .missingPlanningDocs:
            return "Planning documentation is required"
        case .missingDonorAreaAnalysis:
            return "Donor area analysis is required"
        case .missingRecipientAreaAnalysis:
            return "Recipient area analysis is required"
        case .missingGraftCount:
            return "Graft count estimation is required"
        case .missingFutureProjections:
            return "Future projections are required"
        case .missingCulturalPreferences:
            return "Cultural preferences documentation is required"
        case .missingTextureConsiderations:
            return "Texture considerations are required"
        case .invalidPlanningData(let reason):
            return "Invalid planning data: \(reason)"
            
        // Post-operative Instruction Errors
        case .missingPostOpInstructions:
            return "Post-operative instructions are required"
        case .missingDefaultLanguageInstructions:
            return "Default language instructions are missing"
        case .insufficientLanguageSupport:
            return "Additional language support is required"
        case .outdatedInstructions:
            return "Instructions need to be updated to latest version"
        case .invalidInstructionFormat(let reason):
            return "Invalid instruction format: \(reason)"
            
        // Cultural Assessment Errors
        case .missingCulturalAssessment:
            return "Cultural assessment is required"
        case .missingReligiousConsiderations:
            return "Religious considerations documentation is required"
        case .missingTraditionalStyles:
            return "Traditional styles documentation is required"
        case .missingFamilyPatterns:
            return "Family pattern documentation is required"
        case .missingHairTextureAnalysis:
            return "Hair texture analysis is required"
        case .culturalAssessmentIncomplete(let reason):
            return "Cultural assessment incomplete: \(reason)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        // Consent Errors
        case .missingConsent:
            return "Please obtain all required consents before proceeding"
        case .expiredConsent:
            return "Please obtain updated consent from the patient"
        case .invalidConsent:
            return "Review and correct the consent documentation"
            
        // Medical History Errors
        case .missingMedicalHistory:
            return "Complete full medical history documentation"
        case .missingMedicalHistoryField:
            return "Fill in all required medical history fields"
        case .outdatedMedicalHistory:
            return "Update medical history with current information"
            
        // Photo Errors
        case .missingPreoperativePhotos:
            return "Take all required pre-operative photos"
        case .missingPhotoAngle:
            return "Ensure photos are taken from all required angles"
        case .photoQualityBelowThreshold:
            return "Retake photo with better lighting and focus"
            
        // Scan Errors
        case .scanNotCalibrated:
            return "Calibrate device using the calibration wizard"
        case .insufficientLighting:
            return "Move to a well-lit area or add additional lighting"
        case .scanQualityBelowThreshold:
            return "Rescan with slower, more controlled movements"
            
        // Planning Documentation Errors
        case .missingPlanningDocs:
            return "Complete all required planning documentation"
        case .missingDonorAreaAnalysis:
            return "Perform donor area analysis"
        case .missingRecipientAreaAnalysis:
            return "Complete recipient area analysis"
            
        // Post-operative Instruction Errors
        case .insufficientLanguageSupport:
            return "Add support for required languages"
        case .outdatedInstructions:
            return "Update instructions to latest version"
            
        // Cultural Assessment Errors
        case .missingCulturalAssessment:
            return "Complete cultural assessment questionnaire"
        case .missingReligiousConsiderations:
            return "Document religious considerations and requirements"
        case .missingTraditionalStyles:
            return "Document traditional style preferences"
            
        default:
            return "Contact support if the issue persists"
        }
    }
    
    var isRecoverable: Bool {
        switch self {
        case .scanProcessingFailed,
             .invalidMedicalRecord,
             .invalidPlanningData,
             .invalidInstructionFormat:
            return false
        default:
            return true
        }
    }
}