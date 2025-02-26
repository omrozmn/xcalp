import Metal
import MetalKit
import simd

public class MeshRenderer {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var viewportSize: CGSize = .zero
    
    private var uniforms: Uniforms
    private let uniformsBuffer: MTLBuffer
    
    private let mesh: MTKMesh
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    
    struct Uniforms {
        var modelMatrix: float4x4
        var viewMatrix: float4x4
        var projectionMatrix: float4x4
        var normalMatrix: float3x3
    }
    
    public init(device: MTLDevice, mesh: MTKMesh) throws {
        self.device = device
        self.mesh = mesh
        
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        
        // Initialize uniforms
        uniforms = Uniforms(
            modelMatrix: matrix_identity_float4x4,
            viewMatrix: matrix_identity_float4x4,
            projectionMatrix: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float3x3
        )
        
        // Create uniforms buffer
        guard let uniformsBuffer = device.makeBuffer(
            bytes: &uniforms,
            length: MemoryLayout<Uniforms>.size,
            options: [.cpuCacheModeWriteCombined]
        ) else {
            throw RenderError.bufferCreationFailed
        }
        self.uniformsBuffer = uniformsBuffer
        
        // Create render pipeline
        let library = try device.makeDefaultLibrary()
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        
        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            throw RenderError.shaderFunctionNotFound
        }
        
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        
        // Create depth state
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw RenderError.depthStateCreationFailed
        }
        self.depthState = depthState
        
        // Set up vertex and index buffers
        setupBuffers()
    }
    
    private func setupBuffers() {
        guard let vertexBuffer = mesh.vertexBuffers.first?.buffer,
              let indexBuffer = mesh.submeshes.first?.indexBuffer.buffer else {
            return
        }
        
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
    }
    
    public func updateSize(size: CGSize) {
        viewportSize = size
        updateProjectionMatrix()
    }
    
    private func updateProjectionMatrix() {
        let aspect = Float(viewportSize.width / viewportSize.height)
        let fov = Float(70.0 * .pi / 180.0)
        let near: Float = 0.1
        let far: Float = 100.0
        
        uniforms.projectionMatrix = matrix_perspective_right_hand(
            fovyRadians: fov,
            aspectRatio: aspect,
            nearZ: near,
            farZ: far
        )
        
        // Update view matrix
        let eye = SIMD3<Float>(0, 0, -3)
        let center = SIMD3<Float>(0, 0, 0)
        let up = SIMD3<Float>(0, 1, 0)
        
        uniforms.viewMatrix = matrix_look_at_right_hand(
            eye: eye,
            center: center,
            up: up
        )
    }
    
    public func updateModelMatrix(rotation: Float) {
        uniforms.modelMatrix = matrix4x4_rotation(radians: rotation, axis: SIMD3<Float>(0, 1, 0))
        uniforms.normalMatrix = matrix3x3_upper_left(uniforms.modelMatrix)
        
        // Copy updated uniforms to buffer
        memcpy(
            uniformsBuffer.contents(),
            &uniforms,
            MemoryLayout<Uniforms>.size
        )
    }
    
    public func render(
        renderPassDescriptor: MTLRenderPassDescriptor,
        drawable: CAMetalDrawable
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              ) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)
        
        // Draw mesh
        if let submesh = mesh.submeshes.first {
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: indexBuffer!,
                indexBufferOffset: submesh.indexBuffer.offset
            )
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// MARK: - Matrix Math Utilities

private func matrix_perspective_right_hand(
    fovyRadians: Float,
    aspectRatio: Float,
    nearZ: Float,
    farZ: Float
) -> float4x4 {
    let ys = 1 / tanf(fovyRadians * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    
    return float4x4(
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, nearZ * zs, 0)
    )
}

private func matrix_look_at_right_hand(
    eye: SIMD3<Float>,
    center: SIMD3<Float>,
    up: SIMD3<Float>
) -> float4x4 {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    
    let t = float4x4(
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    )
    
    return t
}

private func matrix4x4_rotation(
    radians: Float,
    axis: SIMD3<Float>
) -> float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    
    return float4x4(
        SIMD4<Float>(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        SIMD4<Float>(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
        SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
        SIMD4<Float>(                  0,                   0,                    0, 1)
    )
}

private func matrix3x3_upper_left(_ matrix: float4x4) -> float3x3 {
    return float3x3(
        SIMD3<Float>(matrix[0].x, matrix[0].y, matrix[0].z),
        SIMD3<Float>(matrix[1].x, matrix[1].y, matrix[1].z),
        SIMD3<Float>(matrix[2].x, matrix[2].y, matrix[2].z)
    )
}

enum RenderError: Error {
    case commandQueueCreationFailed
    case bufferCreationFailed
    case shaderFunctionNotFound
    case depthStateCreationFailed
}