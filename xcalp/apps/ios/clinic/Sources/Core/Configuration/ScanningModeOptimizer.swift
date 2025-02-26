import Foundation
import ARKit
import CoreML
import os.log

final class ScanningModeOptimizer {
    private let logger = Logger(subsystem: "com.xcalp.clinic", category: "ScanningModeOptimizer")
    private var currentMode: ScanningMode = .lidar
    private var conditionHistory: [ScanningConditions] = []
    private var performanceMetrics: [String: Float] = [:]
    private var lastModeSwitch: Date = Date()
    private let minTimeBetweenSwitches: TimeInterval = 5.0
    
    enum ScanningMode: String {
        case lidar = "LiDAR"
        case photogrammetry = "Photogrammetry"
        case hybrid = "Hybrid"
    }
    
    struct ScanningConditions {
        let timestamp: Date
        let lightingLevel: Float
        let motionStability: Float
        let surfaceComplexity: Float
        let devicePerformance: Float
        let batteryLevel: Float
    }
    
    struct OptimizationResult {
        let recommendedMode: ScanningMode
        let configurationUpdates: [String: Any]
        let reason: String
    }
    
    func optimizeScanningMode(
        frame: ARFrame,
        currentQuality: MeshQualityAnalyzer.QualityReport
    ) async -> OptimizationResult {
        // Analyze current scanning conditions
        let conditions = try? await analyzeScanningConditions(frame)
        if let conditions = conditions {
            updateConditionHistory(conditions)
        }
        
        // Check if we should consider switching modes
        guard shouldEvaluateMode() else {
            return OptimizationResult(
                recommendedMode: currentMode,
                configurationUpdates: [:],
                reason: "Recent mode switch, maintaining stability"
            )
        }
        
        // Evaluate device capabilities
        let deviceCapabilities = evaluateDeviceCapabilities()
        
        // Determine optimal mode based on conditions and capabilities
        let optimalMode = await determineOptimalMode(
            conditions: conditions,
            quality: currentQuality,
            capabilities: deviceCapabilities
        )
        
        // Generate configuration updates for the new mode
        let updates = generateConfigurationUpdates(
            for: optimalMode,
            conditions: conditions
        )
        
        if optimalMode != currentMode {
            lastModeSwitch = Date()
            currentMode = optimalMode
        }
        
        return OptimizationResult(
            recommendedMode: optimalMode,
            configurationUpdates: updates,
            reason: generateSwitchReason(
                from: currentMode,
                to: optimalMode,
                conditions: conditions
            )
        )
    }
    
    private func analyzeScanningConditions(_ frame: ARFrame) async throws -> ScanningConditions {
        // Analyze lighting conditions
        let lightingLevel = try await calculateLightingLevel(frame)
        
        // Analyze motion stability
        let motionStability = calculateMotionStability(frame)
        
        // Analyze surface complexity
        let surfaceComplexity = try await calculateSurfaceComplexity(frame)
        
        // Get device performance metrics
        let devicePerformance = measureDevicePerformance()
        
        // Get battery level
        let batteryLevel = UIDevice.current.batteryLevel
        
        return ScanningConditions(
            timestamp: Date(),
            lightingLevel: lightingLevel,
            motionStability: motionStability,
            surfaceComplexity: surfaceComplexity,
            devicePerformance: devicePerformance,
            batteryLevel: batteryLevel
        )
    }
    
    private func calculateLightingLevel(_ frame: ARFrame) async throws -> Float {
        guard let capturedImage = frame.capturedImage else {
            throw ScanningError.invalidFrameData
        }
        
        var totalLuminance: Float = 0
        var sampledPixels = 0
        
        // Sample image luminance
        CVPixelBufferLockBaseAddress(capturedImage, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(capturedImage, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(capturedImage) else {
            throw ScanningError.invalidFrameData
        }
        
        let width = CVPixelBufferGetWidth(capturedImage)
        let height = CVPixelBufferGetHeight(capturedImage)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(capturedImage)
        let bytesPerPixel = 4
        
        // Sample every 10th pixel for performance
        for y in stride(from: 0, to: height, by: 10) {
            for x in stride(from: 0, to: width, by: 10) {
                let pixelOffset = y * bytesPerRow + x * bytesPerPixel
                let pixel = baseAddress.advanced(by: pixelOffset)
                    .assumingMemoryBound(to: UInt8.self)
                
                // Convert RGB to luminance
                let r = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let b = Float(pixel[2]) / 255.0
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                totalLuminance += luminance
                sampledPixels += 1
            }
        }
        
        return sampledPixels > 0 ? totalLuminance / Float(sampledPixels) : 0
    }
    
    private func calculateMotionStability(_ frame: ARFrame) -> Float {
        let camera = frame.camera
        let rotationRate = camera.eulerAngles
        let translation = camera.transform.columns.3.xyz
        
        // Calculate motion metrics
        let rotationMagnitude = sqrt(
            rotationRate.x * rotationRate.x +
            rotationRate.y * rotationRate.y +
            rotationRate.z * rotationRate.z
        )
        
        // Track position changes
        let previousPosition = performanceMetrics["lastPosition"] ?? 0
        let positionDelta = abs(translation.y - previousPosition)
        performanceMetrics["lastPosition"] = translation.y
        
        // Combine metrics into stability score
        let rotationStability = 1.0 - min(rotationMagnitude / .pi, 1.0)
        let positionStability = 1.0 - min(positionDelta / 0.1, 1.0)
        
        return (rotationStability + positionStability) / 2.0
    }
    
    private func calculateSurfaceComplexity(_ frame: ARFrame) async throws -> Float {
        guard let sceneDepth = frame.sceneDepth else {
            throw ScanningError.invalidFrameData
        }
        
        var complexity: Float = 0
        let depthMap = sceneDepth.depthMap
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        var depthGradients: [Float] = []
        
        // Calculate depth gradients
        for y in 1..<height-1 {
            for x in 1..<width-1 {
                let center = getDepthValue(depthMap, x: x, y: y, bytesPerRow: bytesPerRow)
                let dx = getDepthValue(depthMap, x: x+1, y: y, bytesPerRow: bytesPerRow) -
                        getDepthValue(depthMap, x: x-1, y: y, bytesPerRow: bytesPerRow)
                let dy = getDepthValue(depthMap, x: x, y: y+1, bytesPerRow: bytesPerRow) -
                        getDepthValue(depthMap, x: x, y: y-1, bytesPerRow: bytesPerRow)
                
                let gradient = sqrt(dx * dx + dy * dy)
                if center > 0 {
                    depthGradients.append(gradient)
                }
            }
        }
        
        // Calculate complexity score based on gradient distribution
        if !depthGradients.isEmpty {
            let meanGradient = depthGradients.reduce(0, +) / Float(depthGradients.count)
            let varianceGradient = depthGradients.reduce(0) { sum, gradient in
                let diff = gradient - meanGradient
                return sum + diff * diff
            } / Float(depthGradients.count)
            
            complexity = sqrt(varianceGradient)
        }
        
        return min(complexity / 0.1, 1.0)
    }
    
    private func measureDevicePerformance() -> Float {
        var performanceScore: Float = 0
        
        // CPU Usage
        var cpuLoad: Float = 0
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        
        let result = task_threads(mach_task_self_, &threadList, &threadCount)
        if result == KERN_SUCCESS, let threadList = threadList {
            for i in 0..<threadCount {
                var threadInfo = thread_basic_info()
                var count = mach_msg_type_number_t(THREAD_BASIC_INFO_COUNT)
                let threadInfoPtr = withUnsafeMutablePointer(to: &threadInfo) {
                    UnsafeMutableRawPointer($0).assumingMemoryBound(to: integer_t.self)
                }
                
                let result = thread_info(threadList[Int(i)],
                                       thread_flavor_t(THREAD_BASIC_INFO),
                                       threadInfoPtr,
                                       &count)
                
                if result == KERN_SUCCESS {
                    let cpuUsage = Float(threadInfo.cpu_usage) / Float(TH_USAGE_SCALE)
                    cpuLoad += cpuUsage
                }
            }
            vm_deallocate(mach_task_self_,
                         vm_address_t(UnsafePointer(threadList).pointee),
                         vm_size_t(threadCount * MemoryLayout<thread_t>.stride))
        }
        
        // Memory Usage
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result2 = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                         task_flavor_t(TASK_VM_INFO),
                         $0,
                         &count)
            }
        }
        
        if result2 == KERN_SUCCESS {
            let memoryUsage = Float(taskInfo.phys_footprint) / Float(ProcessInfo.processInfo.physicalMemory)
            performanceScore = (1.0 - cpuLoad) * 0.6 + (1.0 - memoryUsage) * 0.4
        }
        
        return performanceScore
    }
    
    private func evaluateDeviceCapabilities() -> DeviceCapabilities {
        let lidarAvailable = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        let processingPower = measureDevicePerformance()
        
        return DeviceCapabilities(
            supportsLiDAR: lidarAvailable,
            processingPower: processingPower,
            thermalState: ProcessInfo.processInfo.thermalState
        )
    }
    
    private func determineOptimalMode(
        conditions: ScanningConditions?,
        quality: MeshQualityAnalyzer.QualityReport,
        capabilities: DeviceCapabilities
    ) async -> ScanningMode {
        guard let conditions = conditions else {
            return capabilities.supportsLiDAR ? .lidar : .photogrammetry
        }
        
        // Score different modes based on conditions
        var scores: [ScanningMode: Float] = [:]
        
        // LiDAR scoring
        if capabilities.supportsLiDAR {
            var lidarScore: Float = 0
            lidarScore += conditions.lightingLevel * 0.3
            lidarScore += conditions.motionStability * 0.3
            lidarScore += (1 - conditions.surfaceComplexity) * 0.2
            lidarScore += conditions.devicePerformance * 0.2
            scores[.lidar] = lidarScore
        }
        
        // Photogrammetry scoring
        var photoScore: Float = 0
        photoScore += conditions.lightingLevel * 0.4
        photoScore += conditions.motionStability * 0.3
        photoScore += conditions.surfaceComplexity * 0.2
        photoScore += conditions.devicePerformance * 0.1
        scores[.photogrammetry] = photoScore
        
        // Hybrid scoring
        if capabilities.supportsLiDAR && conditions.devicePerformance > 0.7 {
            var hybridScore: Float = 0
            hybridScore += conditions.lightingLevel * 0.3
            hybridScore += conditions.motionStability * 0.2
            hybridScore += conditions.surfaceComplexity * 0.3
            hybridScore += conditions.devicePerformance * 0.2
            scores[.hybrid] = hybridScore
        }
        
        // Select mode with highest score
        return scores.max(by: { $0.value < $1.value })?.key ?? .photogrammetry
    }
    
    private func generateConfigurationUpdates(
        for mode: ScanningMode,
        conditions: ScanningConditions?
    ) -> [String: Any] {
        var updates: [String: Any] = [:]
        
        switch mode {
        case .lidar:
            updates["frameSemantics"] = [ARFrame.Semantics.sceneDepth,
                                       ARFrame.Semantics.smoothedSceneDepth]
            updates["sceneReconstruction"] = ARWorldTrackingConfiguration.SceneReconstruction.mesh
            
        case .photogrammetry:
            updates["frameSemantics"] = [ARFrame.Semantics.personSegmentation]
            updates["sceneReconstruction"] = ARWorldTrackingConfiguration.SceneReconstruction.none
            
        case .hybrid:
            updates["frameSemantics"] = [ARFrame.Semantics.sceneDepth,
                                       ARFrame.Semantics.smoothedSceneDepth,
                                       ARFrame.Semantics.personSegmentation]
            updates["sceneReconstruction"] = ARWorldTrackingConfiguration.SceneReconstruction.mesh
        }
        
        // Add conditional configuration updates
        if let conditions = conditions {
            updates["motionFilter"] = conditions.motionStability < 0.5 ? "highFidelity" : "balanced"
            updates["environmentTexturing"] = conditions.lightingLevel < 0.3 ? "automatic" : "manual"
        }
        
        return updates
    }
    
    private func generateSwitchReason(
        from currentMode: ScanningMode,
        to newMode: ScanningMode,
        conditions: ScanningConditions?
    ) -> String {
        guard currentMode != newMode else {
            return "Maintaining current mode"
        }
        
        if let conditions = conditions {
            switch newMode {
            case .lidar:
                if conditions.lightingLevel < 0.3 {
                    return "Switching to LiDAR due to low light conditions"
                } else {
                    return "Switching to LiDAR for better accuracy"
                }
                
            case .photogrammetry:
                if conditions.motionStability < 0.5 {
                    return "Switching to photogrammetry due to device motion"
                } else {
                    return "Switching to photogrammetry for better detail"
                }
                
            case .hybrid:
                return "Switching to hybrid mode for optimal quality"
            }
        }
        
        return "Switching modes for optimal performance"
    }
    
    private func shouldEvaluateMode() -> Bool {
        return Date().timeIntervalSince(lastModeSwitch) >= minTimeBetweenSwitches
    }
    
    private func updateConditionHistory(_ conditions: ScanningConditions) {
        conditionHistory.append(conditions)
        if conditionHistory.count > 10 {
            conditionHistory.removeFirst()
        }
    }
    
    private func getDepthValue(_ buffer: CVPixelBuffer, x: Int, y: Int, bytesPerRow: Int) -> Float {
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        return baseAddress!.advanced(by: y * bytesPerRow + x * 4)
            .assumingMemoryBound(to: Float32.self)
            .pointee
    }
}

struct DeviceCapabilities {
    let supportsLiDAR: Bool
    let processingPower: Float
    let thermalState: ProcessInfo.ThermalState
}

private extension simd_float4 {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}