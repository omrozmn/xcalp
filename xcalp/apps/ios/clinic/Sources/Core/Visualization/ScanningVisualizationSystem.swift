import Foundation
import Metal
import MetalKit
import ARKit
import simd

final class ScanningVisualizationSystem {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState
    private var depthState: MTLDepthStencilState
    private var visualizationBuffer: MTLBuffer?
    
    struct VisualizationState {
        var coverageMap: CoverageMap
        var qualityHeatmap: QualityHeatmap
        var guidanceMarkers: [GuidanceMarker]
        var scanProgress: Float
    }
    
    struct CoverageMap {
        var sectors: [Bool]
        var centerPoint: simd_float3
        var radius: Float
    }
    
    struct QualityHeatmap {
        var values: [Float]
        var dimensions: simd_uint2
        var range: ClosedRange<Float>
    }
    
    struct GuidanceMarker {
        var position: simd_float3
        var type: MarkerType
        var importance: Float
        
        enum MarkerType {
            case missingCoverage
            case poorQuality
            case suggestedPath
            case warning
        }
    }
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw VisualizationError.initializationFailed
        }
        self.device = device
        self.commandQueue = commandQueue
        
        // Initialize Metal pipeline
        let library = try device.makeDefaultLibrary()
        let vertexFunction = library.makeFunction(name: "visualizationVertexShader")
        let fragmentFunction = library.makeFunction(name: "visualizationFragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = true
        
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw VisualizationError.initializationFailed
        }
        self.depthState = depthState
    }
    
    func updateVisualization(frame: ARFrame, qualityReport: MeshQualityAnalyzer.QualityReport, guidance: ScanningGuidanceSystem.GuidanceUpdate) {
        let state = generateVisualizationState(frame: frame, qualityReport: qualityReport, guidance: guidance)
        updateBuffers(with: state)
    }
    
    func render(in view: MTKView, with renderPassDescriptor: MTLRenderPassDescriptor) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        
        // Render visualization elements
        renderCoverageMap(encoder: renderEncoder)
        renderQualityHeatmap(encoder: renderEncoder)
        renderGuidanceMarkers(encoder: renderEncoder)
        renderProgressIndicator(encoder: renderEncoder)
        
        renderEncoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
    
    private func generateVisualizationState(
        frame: ARFrame,
        qualityReport: MeshQualityAnalyzer.QualityReport,
        guidance: ScanningGuidanceSystem.GuidanceUpdate
    ) -> VisualizationState {
        // Generate coverage map
        let coverageMap = generateCoverageMap(from: frame)
        
        // Generate quality heatmap
        let heatmap = generateQualityHeatmap(from: qualityReport)
        
        // Generate guidance markers
        let markers = generateGuidanceMarkers(from: guidance)
        
        // Calculate overall progress
        let progress = calculateScanProgress(
            coverage: coverageMap,
            quality: qualityReport
        )
        
        return VisualizationState(
            coverageMap: coverageMap,
            qualityHeatmap: heatmap,
            guidanceMarkers: markers,
            scanProgress: progress
        )
    }
    
    private func generateCoverageMap(from frame: ARFrame) -> CoverageMap {
        let camera = frame.camera
        let position = camera.transform.columns.3.xyz
        
        // Calculate scanning sectors
        var sectors = [Bool](repeating: false, count: 8)
        let angle = atan2(camera.eulerAngles.y, camera.eulerAngles.x)
        let sector = Int((angle + .pi) / (.pi / 4)) % 8
        sectors[sector] = true
        
        return CoverageMap(
            sectors: sectors,
            centerPoint: position,
            radius: 1.0
        )
    }
    
    private func generateQualityHeatmap(from report: MeshQualityAnalyzer.QualityReport) -> QualityHeatmap {
        let dimensions = simd_uint2(32, 32)
        var values = [Float](repeating: 0, count: Int(dimensions.x * dimensions.y))
        
        // Map quality metrics to heatmap values
        for y in 0..<Int(dimensions.y) {
            for x in 0..<Int(dimensions.x) {
                let index = y * Int(dimensions.x) + x
                let quality = calculateLocalQuality(
                    x: Float(x) / Float(dimensions.x),
                    y: Float(y) / Float(dimensions.y),
                    report: report
                )
                values[index] = quality
            }
        }
        
        return QualityHeatmap(
            values: values,
            dimensions: dimensions,
            range: 0...1
        )
    }
    
    private func generateGuidanceMarkers(from guidance: ScanningGuidanceSystem.GuidanceUpdate) -> [GuidanceMarker] {
        var markers: [GuidanceMarker] = []
        
        // Convert guidance suggestions to visual markers
        if let action = guidance.suggestedAction {
            switch action {
            case .moveCloser:
                markers.append(GuidanceMarker(
                    position: simd_float3(0, 0, -0.5),
                    type: .suggestedPath,
                    importance: 1.0
                ))
            case .moveFurther:
                markers.append(GuidanceMarker(
                    position: simd_float3(0, 0, 0.5),
                    type: .suggestedPath,
                    importance: 1.0
                ))
            case .scanMissingArea(let area):
                markers.append(GuidanceMarker(
                    position: simd_float3(
                        Float(area.midX),
                        Float(area.midY),
                        0
                    ),
                    type: .missingCoverage,
                    importance: 1.0
                ))
            default:
                break
            }
        }
        
        return markers
    }
    
    private func calculateScanProgress(coverage: CoverageMap, quality: MeshQualityAnalyzer.QualityReport) -> Float {
        let coverageProgress = Float(coverage.sectors.filter { $0 }.count) / Float(coverage.sectors.count)
        let qualityProgress = quality.surfaceCompleteness
        
        return (coverageProgress + qualityProgress) / 2.0
    }
    
    private func calculateLocalQuality(x: Float, y: Float, report: MeshQualityAnalyzer.QualityReport) -> Float {
        // Combine multiple quality metrics into a single value
        let densityFactor = min(report.pointDensity / MeshQualityConfig.minimumPointDensity, 1.0)
        let completenessFactor = report.surfaceCompleteness
        let featureFactor = report.featurePreservation
        
        return (densityFactor + completenessFactor + featureFactor) / 3.0
    }
    
    private func updateBuffers(with state: VisualizationState) {
        // Update Metal buffers with new visualization data
        let bufferSize = MemoryLayout<VisualizationState>.size
        visualizationBuffer = device.makeBuffer(
            bytes: &state,
            length: bufferSize,
            options: .storageModeShared
        )
    }
    
    private func renderCoverageMap(encoder: MTLRenderCommandEncoder) {
        guard let buffer = visualizationBuffer else { return }
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }
    
    private func renderQualityHeatmap(encoder: MTLRenderCommandEncoder) {
        guard let buffer = visualizationBuffer else { return }
        encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 6, vertexCount: 6)
    }
    
    private func renderGuidanceMarkers(encoder: MTLRenderCommandEncoder) {
        guard let buffer = visualizationBuffer else { return }
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 12, vertexCount: 1)
    }
    
    private func renderProgressIndicator(encoder: MTLRenderCommandEncoder) {
        guard let buffer = visualizationBuffer else { return }
        encoder.setVertexBuffer(buffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .lineStrip, vertexStart: 13, vertexCount: 2)
    }
}

enum VisualizationError: Error {
    case initializationFailed
}

private extension simd_float4 {
    var xyz: simd_float3 {
        return simd_float3(x, y, z)
    }
}