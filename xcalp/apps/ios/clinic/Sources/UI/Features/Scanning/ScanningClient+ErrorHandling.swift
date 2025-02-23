// ...existing imports...
import os.log

extension ScanningClient {
    private static func validateMesh(_ mesh: MeshProcessor.ProcessedMesh) throws {
        var issues: [MeshIssue] = []
        
        // Check vertex count
        let minimumVertices = 1000
        if mesh.metrics.optimizedVertexCount < minimumVertices {
            issues.append(.tooFewVertices(
                count: mesh.metrics.optimizedVertexCount,
                minimum: minimumVertices
            ))
        }
        
        // Check vertex density
        let minimumDensity: Float = 0.5 // vertices per cubic cm
        if mesh.quality.vertexDensity < minimumDensity {
            issues.append(.poorVertexDensity(
                density: mesh.quality.vertexDensity,
                minimum: minimumDensity
            ))
        }
        
        // Check normal consistency
        let minimumConsistency: Float = 0.8
        if mesh.quality.normalConsistency < minimumConsistency {
            issues.append(.inconsistentNormals(
                consistency: mesh.quality.normalConsistency,
                minimum: minimumConsistency
            ))
        }
        
        // Check for holes
        let maximumHoles = 5
        if mesh.quality.holes.count > maximumHoles {
            issues.append(.tooManyHoles(count: mesh.quality.holes.count))
        }
        
        if !issues.isEmpty {
            throw ScanningError.meshValidationFailed(issues: issues)
        }
    }
    
    private static func checkSystemRequirements() throws {
        let monitor = PerformanceMonitor.shared
        
        // Check thermal state
        if ProcessInfo.processInfo.thermalState == .critical {
            throw ScanningError.thermalThrottling
        }
        
        // Check available memory
        if !monitor.meetsPerformanceRequirements() {
            throw ScanningError.insufficientMemory
        }
    }
    
    func handleScanningError(_ error: Error) async throws {
        logger.error("Scanning error: \(error.localizedDescription)")
        
        // Try to recover from common errors
        switch error {
        case ARError.deviceNotSupported:
            throw ScanningError.deviceNotCapable
            
        case ARError.sensorUnavailable:
            // Try reinitializing LiDAR with delay
            try await Task.sleep(nanoseconds: 2_000_000_000)
            try await initializeLidarSession()
            
        case ARError.worldTrackingFailed:
            // Reset tracking and retry
            arSession.run(ARWorldTrackingConfiguration(), options: [.resetTracking, .removeExistingAnchors])
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
        case ScanningError.noMeshDataAvailable:
            // Wait longer for mesh generation and retry
            try await Task.sleep(nanoseconds: 3_000_000_000)
            try await scanWithTimeout()
            
        default:
            // Log error details securely for HIPAA compliance
            await SecureLogger.shared.logError(
                domain: "Scanning",
                error: error,
                severity: .high,
                additionalInfo: [
                    "deviceModel": UIDevice.current.model,
                    "systemVersion": UIDevice.current.systemVersion,
                    "scanningMode": currentScanningMode.rawValue
                ]
            )
            throw error
        }
    }
    
    func scanWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Add timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 second timeout
                throw ScanningError.timeout
            }
            
            // Add scanning task
            group.addTask {
                try await performScanning()
            }
            
            // Wait for first completion/error
            try await group.next()
            group.cancelAll()
        }
    }
}

extension ScanningClient.live {
    public var captureScan: @Sendable () async throws -> Data {
        return {
            let perfID = PerformanceMonitor.shared.startMeasuring(
                "scanCapture",
                category: "scanning"
            )
            
            // Check system requirements
            try checkSystemRequirements()
            
            // Initialize and configure LiDAR
            let session = try await initializeLidarSession()
            
            // Wait for mesh data with timeout
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                }
                
                group.addTask {
                    try await withTimeout(seconds: 10) {
                        // Get mesh data
                        let meshAnchors = session.currentFrame?.anchors.compactMap { $0 as? ARMeshAnchor } ?? []
                        
                        if meshAnchors.isEmpty {
                            throw ScanningError.processingFailed(reason: "No mesh data available")
                        }
                        
                        // Process mesh...
                        // (rest of existing mesh processing code)
                        
                        let processedMesh = try await meshProcessor.processMesh(meshData)
                        
                        // Validate processed mesh
                        try validateMesh(processedMesh)
                        
                        // Log metrics...
                        // (rest of existing analytics code)
                    }
                }
            }
            
            session.pause()
            
            PerformanceMonitor.shared.endMeasuring(
                "scanCapture",
                signpostID: perfID,
                category: "scanning"
            )
            
            return try encoder.encode(ScanData(
                mesh: processedMesh,
                settings: .default,
                deviceInfo: .current,
                environmentInfo: .current
            ))
        }
    }
}