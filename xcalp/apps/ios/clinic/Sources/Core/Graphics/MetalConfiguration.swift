import Foundation
import Metal
import MetalPerformanceShaders

public actor MetalConfiguration {
    public static let shared = MetalConfiguration()
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let performanceMonitor: PerformanceMonitor
    private let analytics: AnalyticsService
    
    private var currentPrecision: FloatingPointPrecision = .full
    private var activePipelines: Set<String> = []
    private var pipelineStates: [String: MTLComputePipelineState] = [:]
    private var powerMode: PowerMode = .balanced
    
    private init(
        performanceMonitor: PerformanceMonitor = .shared,
        analytics: AnalyticsService = .shared
    ) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.deviceNotAvailable
        }
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.commandQueueCreationFailed
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.performanceMonitor = performanceMonitor
        self.analytics = analytics
        
        setupInitialConfiguration()
    }
    
    public func reducePrecision() async {
        switch currentPrecision {
        case .full:
            await switchPrecision(to: .half)
        case .half:
            await switchPrecision(to: .reduced)
        case .reduced:
            // Already at lowest precision
            break
        }
    }
    
    public func disableNonEssentialPipelines() async {
        let nonEssentialPipelines = activePipelines.filter { !isEssentialPipeline($0) }
        
        for pipeline in nonEssentialPipelines {
            await disablePipeline(pipeline)
        }
        
        analytics.track(
            event: .pipelinesDisabled,
            properties: [
                "count": nonEssentialPipelines.count,
                "pipelines": nonEssentialPipelines
            ]
        )
    }
    
    public func minimumPowerMode() async {
        powerMode = .minimum
        
        // Configure device for minimum power
        await configureForMinimumPower()
        
        analytics.track(
            event: .powerModeChanged,
            properties: ["mode": "minimum"]
        )
    }
    
    public func configurePipeline(
        _ name: String,
        function: String,
        isEssential: Bool = false
    ) async throws -> MTLComputePipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryCreationFailed
        }
        
        guard let function = library.makeFunction(name: function) else {
            throw MetalError.functionNotFound
        }
        
        let pipelineState = try device.makeComputePipelineState(function: function)
        pipelineStates[name] = pipelineState
        activePipelines.insert(name)
        
        analytics.track(
            event: .pipelineConfigured,
            properties: [
                "name": name,
                "isEssential": isEssential
            ]
        )
        
        return pipelineState
    }
    
    public func getCommandBuffer() -> MTLCommandBuffer? {
        return commandQueue.makeCommandBuffer()
    }
    
    private func setupInitialConfiguration() {
        // Set initial power state
        powerMode = .balanced
        
        // Configure initial precision
        currentPrecision = .full
        
        // Setup performance monitoring
        setupPerformanceMonitoring()
    }
    
    private func switchPrecision(to precision: FloatingPointPrecision) async {
        let oldPrecision = currentPrecision
        currentPrecision = precision
        
        // Reconfigure active pipelines for new precision
        await reconfigurePipelines()
        
        analytics.track(
            event: .precisionChanged,
            properties: [
                "oldPrecision": oldPrecision.rawValue,
                "newPrecision": precision.rawValue
            ]
        )
    }
    
    private func reconfigurePipelines() async {
        // Implementation for reconfiguring pipelines
    }
    
    private func disablePipeline(_ name: String) async {
        pipelineStates.removeValue(forKey: name)
        activePipelines.remove(name)
    }
    
    private func isEssentialPipeline(_ name: String) -> Bool {
        // Define essential pipelines
        let essentialPipelines = Set([
            "scanProcessing",
            "meshGeneration",
            "textureMapping"
        ])
        
        return essentialPipelines.contains(name)
    }
    
    private func configureForMinimumPower() async {
        // Set device to lowest power state
        await switchPrecision(to: .reduced)
        
        // Disable all non-essential features
        await disableNonEssentialPipelines()
        
        // Reduce memory usage
        await cleanupUnusedResources()
    }
    
    private func cleanupUnusedResources() async {
        // Implementation for resource cleanup
    }
    
    private func setupPerformanceMonitoring() {
        Task {
            for await metrics in performanceMonitor.gpuMetrics() {
                await handleGPUMetrics(metrics)
            }
        }
    }
    
    private func handleGPUMetrics(_ metrics: GPUMetrics) async {
        if metrics.utilizationPercent > 90 {
            await reducePrecision()
        }
        
        if metrics.temperature > 80 {
            await minimumPowerMode()
        }
    }
}

// MARK: - Types

extension MetalConfiguration {
    public enum FloatingPointPrecision: String {
        case full      // Float32
        case half      // Float16
        case reduced   // Custom reduced precision
    }
    
    public enum PowerMode {
        case maximum
        case balanced
        case efficient
        case minimum
    }
    
    public enum MetalError: LocalizedError {
        case deviceNotAvailable
        case commandQueueCreationFailed
        case libraryCreationFailed
        case functionNotFound
        case pipelineCreationFailed
        
        public var errorDescription: String? {
            switch self {
            case .deviceNotAvailable:
                return "Metal device not available"
            case .commandQueueCreationFailed:
                return "Failed to create command queue"
            case .libraryCreationFailed:
                return "Failed to create Metal library"
            case .functionNotFound:
                return "Metal function not found"
            case .pipelineCreationFailed:
                return "Failed to create compute pipeline"
            }
        }
    }
    
    struct GPUMetrics {
        let utilizationPercent: Float
        let temperature: Float
        let powerConsumption: Float
    }
}

extension AnalyticsService.Event {
    static let pipelinesDisabled = AnalyticsService.Event(name: "metal_pipelines_disabled")
    static let powerModeChanged = AnalyticsService.Event(name: "metal_power_mode_changed")
    static let pipelineConfigured = AnalyticsService.Event(name: "metal_pipeline_configured")
    static let precisionChanged = AnalyticsService.Event(name: "metal_precision_changed")
}