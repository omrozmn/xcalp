import Foundation

class ClinicalWorkflowManager {
    static let shared = ClinicalWorkflowManager()
    
    private var currentRegion: Region
    private let regionManager = RegionalComplianceManager.shared
    
    private var workflowRequirements: [Region: [WorkflowStep]] = [
        .unitedStates: [
            .patientConsent([.hipaa, .photography]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures"]),
            .preoperativePhotos(angles: [0, 45, 90, 180, 270, 315]),
            .scan(requirements: [.calibration, .lightingCheck]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount]),
            .postoperativeInstructions(format: .bilingual)
        ],
        .europeanUnion: [
            .patientConsent([.gdpr, .photography, .dataProcessing]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures", "family_history"]),
            .preoperativePhotos(angles: [0, 45, 90, 135, 180, 225, 270, 315]),
            .scan(requirements: [.calibration, .lightingCheck, .qualityVerification]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount, .futureProjections]),
            .postoperativeInstructions(format: .multilingual)
        ],
        .turkey: [
            .patientConsent([.kvkk, .photography]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures"]),
            .preoperativePhotos(angles: [0, 45, 90, 180, 270, 315]),
            .scan(requirements: [.calibration, .lightingCheck]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount]),
            .postoperativeInstructions(format: .bilingual)
        ],
        .southAsia: [
            .patientConsent([.dataProcessing, .photography, .culturalConsideration]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures", "religious_considerations"]),
            .preoperativePhotos(angles: [0, 45, 90, 135, 180, 225, 270, 315]),
            .culturalAssessment(includes: [.religiousRequirements, .traditionalStyles]),
            .scan(requirements: [.calibration, .lightingCheck, .qualityVerification]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount, .culturalPreferences]),
            .postoperativeInstructions(format: .multilingual)
        ],
        .mediterranean: [
            .patientConsent([.dataProcessing, .photography, .culturalConsideration]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures", "family_pattern"]),
            .preoperativePhotos(angles: [0, 45, 90, 135, 180, 225, 270, 315]),
            .culturalAssessment(includes: [.traditionalStyles, .familyPatterns]),
            .scan(requirements: [.calibration, .lightingCheck, .qualityVerification]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount, .culturalPreferences]),
            .postoperativeInstructions(format: .bilingual)
        ],
        .africanDescent: [
            .patientConsent([.dataProcessing, .photography]),
            .medicalHistory(requiredFields: ["allergies", "medications", "previous_procedures", "hair_care_routine"]),
            .preoperativePhotos(angles: [0, 45, 90, 135, 180, 225, 270, 315]),
            .culturalAssessment(includes: [.hairTexture, .traditionalStyles]),
            .scan(requirements: [.calibration, .lightingCheck, .qualityVerification, .textureAnalysis]),
            .planningDocumentation(includes: [.donorArea, .recipientArea, .graftCount, .culturalPreferences, .textureConsiderations]),
            .postoperativeInstructions(format: .multilingual)
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
    
    func getRequiredSteps() -> [WorkflowStep] {
        return workflowRequirements[currentRegion] ?? []
    }
    
    func validateWorkflowCompliance(_ clinicalCase: ClinicalCase) throws {
        let requiredSteps = getRequiredSteps()
        
        for step in requiredSteps {
            try validateStep(step, in: clinicalCase)
        }
    }
    
    private func validateStep(_ step: WorkflowStep, in clinicalCase: ClinicalCase) throws {
        switch step {
        case .patientConsent(let requiredConsents):
            try validateConsents(requiredConsents, in: clinicalCase)
            
        case .medicalHistory(let requiredFields):
            try validateMedicalHistory(requiredFields, in: clinicalCase)
            
        case .preoperativePhotos(let angles):
            try validatePhotos(angles, in: clinicalCase)
            
        case .scan(let requirements):
            try validateScanRequirements(requirements, in: clinicalCase)
            
        case .planningDocumentation(let includes):
            try validatePlanningDocs(includes, in: clinicalCase)
            
        case .postoperativeInstructions(let format):
            try validatePostOpInstructions(format, in: clinicalCase)
            
        case .culturalAssessment(let includes):
            try validateCulturalAssessment(includes, in: clinicalCase)
        }
    }
}

// MARK: - Supporting Types

enum WorkflowStep {
    case patientConsent([ConsentType])
    case medicalHistory(requiredFields: [String])
    case preoperativePhotos(angles: [Int])
    case scan(requirements: Set<ScanRequirement>)
    case planningDocumentation(includes: Set<PlanningDocumentType>)
    case postoperativeInstructions(format: InstructionFormat)
    case culturalAssessment(includes: Set<CulturalAssessmentType>)
}

enum ScanRequirement {
    case calibration
    case lightingCheck
    case qualityVerification
    case textureAnalysis
}

enum PlanningDocumentType {
    case donorArea
    case recipientArea
    case graftCount
    case futureProjections
    case culturalPreferences
    case textureConsiderations
}

enum InstructionFormat {
    case standard
    case bilingual
    case multilingual
}

enum CulturalAssessmentType {
    case religiousRequirements
    case traditionalStyles
    case familyPatterns
    case hairTexture
}

enum ConsentType {
    case hipaa
    case gdpr
    case kvkk
    case photography
    case dataProcessing
    case culturalConsideration
}

// MARK: - Private Extensions

private extension ClinicalWorkflowManager {
    func validateConsents(_ required: [ConsentType], in case: ClinicalCase) throws {
        for consent in required {
            guard let patientConsents = case.patientConsents,
                  patientConsents.contains(consent) else {
                throw WorkflowError.missingConsent(consent)
            }
            
            // Validate consent timestamp is within acceptable range
            if let consentDate = case.consentDates[consent],
               Calendar.current.dateComponents([.month], from: consentDate, to: Date()).month ?? 0 > 12 {
                throw WorkflowError.expiredConsent(consent)
            }
        }
    }
    
    func validateMedicalHistory(_ required: [String], in case: ClinicalCase) throws {
        guard let history = case.medicalHistory else {
            throw WorkflowError.missingMedicalHistory
        }
        
        for field in required {
            guard let value = history[field], !value.isEmpty else {
                throw WorkflowError.missingMedicalHistoryField(field)
            }
        }
        
        // Validate history timestamp
        guard let lastUpdated = history.lastUpdated,
              Calendar.current.dateComponents([.month], from: lastUpdated, to: Date()).month ?? 0 <= 6 else {
            throw WorkflowError.outdatedMedicalHistory
        }
    }
    
    func validatePhotos(_ angles: [Int], in case: ClinicalCase) throws {
        guard let photos = case.preoperativePhotos else {
            throw WorkflowError.missingPreoperativePhotos
        }
        
        let photoAngles = photos.map { $0.angle }
        for requiredAngle in angles {
            guard photoAngles.contains(requiredAngle) else {
                throw WorkflowError.missingPhotoAngle(requiredAngle)
            }
        }
        
        // Validate photo quality
        for photo in photos {
            guard photo.qualityScore >= AppConfig.minimumPhotoQuality else {
                throw WorkflowError.photoQualityBelowThreshold(angle: photo.angle)
            }
        }
    }
    
    func validateScanRequirements(_ requirements: Set<ScanRequirement>, in case: ClinicalCase) throws {
        guard let scan = case.scan else {
            throw WorkflowError.missingScan
        }
        
        for requirement in requirements {
            switch requirement {
            case .calibration:
                guard scan.isCalibrated else {
                    throw WorkflowError.scanNotCalibrated
                }
            case .lightingCheck:
                guard scan.lightingScore >= AppConfig.minimumLightingScore else {
                    throw WorkflowError.insufficientLighting
                }
            case .qualityVerification:
                guard scan.qualityScore >= AppConfig.minimumScanQuality else {
                    throw WorkflowError.scanQualityBelowThreshold
                }
            case .textureAnalysis:
                guard scan.textureAnalysisComplete else {
                    throw WorkflowError.missingTextureAnalysis
                }
            }
        }
    }
    
    func validatePlanningDocs(_ includes: Set<PlanningDocumentType>, in case: ClinicalCase) throws {
        guard let planning = case.planningDocumentation else {
            throw WorkflowError.missingPlanningDocs
        }
        
        for docType in includes {
            switch docType {
            case .donorArea:
                guard planning.hasDonorAreaAnalysis else {
                    throw WorkflowError.missingDonorAreaAnalysis
                }
            case .recipientArea:
                guard planning.hasRecipientAreaAnalysis else {
                    throw WorkflowError.missingRecipientAreaAnalysis
                }
            case .graftCount:
                guard planning.hasGraftCountEstimation else {
                    throw WorkflowError.missingGraftCount
                }
            case .futureProjections:
                guard planning.hasFutureProjections else {
                    throw WorkflowError.missingFutureProjections
                }
            case .culturalPreferences:
                guard planning.hasCulturalPreferences else {
                    throw WorkflowError.missingCulturalPreferences
                }
            case .textureConsiderations:
                guard planning.hasTextureConsiderations else {
                    throw WorkflowError.missingTextureConsiderations
                }
            }
        }
    }
    
    func validatePostOpInstructions(_ format: InstructionFormat, in case: ClinicalCase) throws {
        guard let instructions = case.postOperativeInstructions else {
            throw WorkflowError.missingPostOpInstructions
        }
        
        switch format {
        case .standard:
            guard instructions.hasDefaultLanguage else {
                throw WorkflowError.missingDefaultLanguageInstructions
            }
        case .bilingual:
            guard instructions.supportedLanguages.count >= 2 else {
                throw WorkflowError.insufficientLanguageSupport
            }
        case .multilingual:
            guard instructions.supportedLanguages.count >= 3 else {
                throw WorkflowError.insufficientLanguageSupport
            }
        }
        
        // Validate instructions are up to date
        guard instructions.version >= AppConfig.minimumInstructionsVersion else {
            throw WorkflowError.outdatedInstructions
        }
    }
    
    func validateCulturalAssessment(_ includes: Set<CulturalAssessmentType>, in case: ClinicalCase) throws {
        guard let assessment = case.culturalAssessment else {
            throw WorkflowError.missingCulturalAssessment
        }
        
        for requirement in includes {
            switch requirement {
            case .religiousRequirements:
                guard assessment.religiousConsiderationsDocumented else {
                    throw WorkflowError.missingReligiousConsiderations
                }
            case .traditionalStyles:
                guard assessment.traditionalStylesDocumented else {
                    throw WorkflowError.missingTraditionalStyles
                }
            case .familyPatterns:
                guard assessment.familyPatternsDocumented else {
                    throw WorkflowError.missingFamilyPatterns
                }
            case .hairTexture:
                guard assessment.hairTextureDocumented else {
                    throw WorkflowError.missingHairTextureAnalysis
                }
            }
        }
    }
}