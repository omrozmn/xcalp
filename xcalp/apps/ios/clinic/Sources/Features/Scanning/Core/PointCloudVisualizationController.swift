import RealityKit
import Metal
import simd

public enum VisualizationMode {
    case points
    case mesh
    case wireframe
    case heatmap
}

public class PointCloudVisualizationController {
    private let device: MTLDevice
    private var currentMode: VisualizationMode = .points
    private let pointSize: Float = 5.0
    private let depthColorProcessor = DepthColorProcessor()
    
    private var heatmapColors: [SIMD4<Float>] = [
        SIMD4<Float>(0.0, 0.0, 1.0, 1.0),  // Blue (cold)
        SIMD4<Float>(0.0, 1.0, 1.0, 1.0),  // Cyan
        SIMD4<Float>(0.0, 1.0, 0.0, 1.0),  // Green
        SIMD4<Float>(1.0, 1.0, 0.0, 1.0),  // Yellow
        SIMD4<Float>(1.0, 0.0, 0.0, 1.0)   // Red (hot)
    ]
    
    init(device: MTLDevice) {
        self.device = device
    }
    
    func updateVisualization(
        points: [Point3D],
        quality: Float,
        mode: VisualizationMode
    ) -> ModelEntity? {
        currentMode = mode
        
        // Process points with depth coloring
        let coloredPoints = depthColorProcessor.processPoints(points)
        
        switch mode {
        case .points:
            return createPointCloud(from: coloredPoints)
        case .mesh:
            return createMesh(from: coloredPoints)
        case .wireframe:
            return createWireframe(from: coloredPoints)
        case .heatmap:
            return createHeatmap(from: points, quality: quality)
        }
    }
    
    private func createPointCloud(
        from points: [(point: Point3D, color: SIMD4<Float>)]
    ) -> ModelEntity? {
        var vertices: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        
        for point in points {
            vertices.append(SIMD3<Float>(point.point.x, point.point.y, point.point.z))
            colors.append(point.color)
        }
        
        let descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.colors = MeshBuffer(colors)
        
        // Create point cloud material with vertex colors
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        
        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        } catch {
            print("Failed to create point cloud: \(error)")
            return nil
        }
    }
    
    private func createMesh(
        from points: [(point: Point3D, color: SIMD4<Float>)]
    ) -> ModelEntity? {
        var vertices: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        
        for point in points {
            vertices.append(SIMD3<Float>(point.point.x, point.point.y, point.point.z))
            colors.append(point.color)
        }
        
        let descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.colors = MeshBuffer(colors)
        
        // Create mesh material with vertex colors
        var material = SimpleMaterial()
        material.baseColor = .init(tint: .white)
        material.roughness = .init(floatLiteral: 0.5)
        material.metallic = .init(floatLiteral: 0.0)
        
        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        } catch {
            print("Failed to create mesh: \(error)")
            return nil
        }
    }
    
    private func createWireframe(
        from points: [(point: Point3D, color: SIMD4<Float>)]
    ) -> ModelEntity? {
        var vertices: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        
        for point in points {
            vertices.append(SIMD3<Float>(point.point.x, point.point.y, point.point.z))
            colors.append(point.color)
        }
        
        let descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.colors = MeshBuffer(colors)
        
        // Create wireframe material with vertex colors
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        
        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        } catch {
            print("Failed to create wireframe: \(error)")
            return nil
        }
    }
    
    private func createHeatmap(from points: [Point3D], quality: Float) -> ModelEntity? {
        var vertices: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        
        for point in points {
            vertices.append(SIMD3<Float>(point.x, point.y, point.z))
            colors.append(getHeatmapColor(for: quality))
        }
        
        let descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(vertices)
        descriptor.colors = MeshBuffer(colors)
        
        // Create heatmap material
        var material = UnlitMaterial()
        material.color = .init(tint: .white)
        
        do {
            let mesh = try MeshResource.generate(from: [descriptor])
            let entity = ModelEntity(mesh: mesh, materials: [material])
            return entity
        } catch {
            print("Failed to create heatmap: \(error)")
            return nil
        }
    }
    
    private func getHeatmapColor(for quality: Float) -> SIMD4<Float> {
        let index = Int(quality * Float(heatmapColors.count - 1))
        let boundedIndex = max(0, min(heatmapColors.count - 1, index))
        return heatmapColors[boundedIndex]
    }
}