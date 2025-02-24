extension ScanVisualizationHelper {
    public func updateClinicalGuides(in arView: ARView, performance: ScanningPerformance) {
        // Update visual guidance based on clinical thresholds
        let coverageIndicator = generateCoverageIndicator(
            coverage: performance.coverage,
            minimumRequired: ClinicalConstants.densityMappingAccuracy
        )
        
        let stabilityIndicator = generateStabilityIndicator(
            stability: performance.stability,
            threshold: ClinicalConstants.surfaceConsistencyThreshold
        )
        
        let qualityIndicator = generateQualityIndicator(
            featureConfidence: performance.featureMatchConfidence,
            threshold: ClinicalConstants.featureDetectionConfidence,
            reprojectionError: performance.reprojectionError,
            maxError: ClinicalConstants.maxReprojectionError
        )
        
        // Position indicators in AR space
        positionGuides(
            coverageIndicator: coverageIndicator,
            stabilityIndicator: stabilityIndicator,
            qualityIndicator: qualityIndicator,
            in: arView
        )
    }
    
    private func generateCoverageIndicator(coverage: Float, minimumRequired: Float) -> ModelEntity {
        let mesh = MeshResource.generateRing(
            radius: 0.05,
            thickness: 0.005,
            progress: coverage / minimumRequired
        )
        
        let material = SimpleMaterial(
            color: coverage >= minimumRequired ? .green : .yellow,
            roughness: 0.5,
            isMetallic: true
        )
        
        return ModelEntity(mesh: mesh, materials: [material])
    }
    
    private func generateStabilityIndicator(stability: Float, threshold: Float) -> ModelEntity {
        let color: UIColor = stability >= threshold ? .green : .red
        let mesh = MeshResource.generatePlane(width: 0.03, depth: 0.03)
        let material = SimpleMaterial(color: color.withAlphaComponent(0.7))
        
        return ModelEntity(mesh: mesh, materials: [material])
    }
    
    private func generateQualityIndicator(
        featureConfidence: Float,
        threshold: Float,
        reprojectionError: Float,
        maxError: Float
    ) -> ModelEntity {
        let color: UIColor
        if featureConfidence >= threshold && reprojectionError <= maxError {
            color = .green
        } else if featureConfidence >= threshold * 0.8 || reprojectionError <= maxError * 1.2 {
            color = .yellow
        } else {
            color = .red
        }
        
        let mesh = MeshResource.generateSphere(radius: 0.01)
        let material = SimpleMaterial(color: color, isMetallic: true)
        
        return ModelEntity(mesh: mesh, materials: [material])
    }
    
    private func positionGuides(
        coverageIndicator: ModelEntity,
        stabilityIndicator: ModelEntity,
        qualityIndicator: ModelEntity,
        in arView: ARView
    ) {
        // Create anchor in camera space
        let anchor = AnchorEntity(.camera)
        
        // Position coverage indicator center-right
        coverageIndicator.position = SIMD3(x: 0.1, y: 0, z: -0.3)
        
        // Position stability indicator top-center
        stabilityIndicator.position = SIMD3(x: 0, y: 0.1, z: -0.3)
        
        // Position quality indicator top-right
        qualityIndicator.position = SIMD3(x: 0.1, y: 0.1, z: -0.3)
        
        // Add all indicators to anchor
        anchor.addChild(coverageIndicator)
        anchor.addChild(stabilityIndicator)
        anchor.addChild(qualityIndicator)
        
        // Add anchor to scene
        arView.scene.addAnchor(anchor)
    }
}
