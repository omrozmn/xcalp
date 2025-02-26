import Foundation
import Accelerate
import Metal

actor ConjugateGradientSolver {
    private let maxIterations: Int
    private let tolerance: Float
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    
    init(maxIterations: Int = 1000, tolerance: Float = 1e-6, useGPU: Bool = true) {
        self.maxIterations = maxIterations
        self.tolerance = tolerance
        
        if useGPU {
            self.device = MTLCreateSystemDefaultDevice()
            self.commandQueue = device?.makeCommandQueue()
        }
    }
    
    func solve(A: SparseMatrix, b: [Float]) async throws -> [Float] {
        if let device = device, let commandQueue = commandQueue {
            return try await solveGPU(A: A, b: b, device: device, commandQueue: commandQueue)
        } else {
            return try solveCPU(A: A, b: b)
        }
    }
    
    private func solveCPU(A: SparseMatrix, b: [Float]) throws -> [Float] {
        let n = b.count
        var x = [Float](repeating: 0, count: n)
        var r = b
        var p = b
        
        // Initial residual
        let Ax = A.multiply(x)
        vDSP_vsub(Ax, 1, b, 1, &r, 1, vDSP_Length(n))
        
        var rsold: Float = 0
        vDSP_dotpr(r, 1, r, 1, &rsold, vDSP_Length(n))
        
        for iteration in 0..<maxIterations {
            // Matrix-vector multiplication
            let Ap = A.multiply(p)
            
            // Step size
            var alpha: Float = 0
            var pAp: Float = 0
            vDSP_dotpr(p, 1, Ap, 1, &pAp, vDSP_Length(n))
            alpha = rsold / pAp
            
            // Update solution and residual
            vDSP_vsma(p, 1, &alpha, x, 1, &x, 1, vDSP_Length(n))
            vDSP_vsma(Ap, 1, &alpha, r, 1, &r, 1, vDSP_Length(n))
            
            // New residual norm
            var rsnew: Float = 0
            vDSP_dotpr(r, 1, r, 1, &rsnew, vDSP_Length(n))
            
            // Check convergence
            if sqrt(rsnew) < tolerance {
                return x
            }
            
            // Update direction
            let beta = rsnew / rsold
            vDSP_vsmul(p, 1, &beta, &p, 1, vDSP_Length(n))
            vDSP_vadd(r, 1, p, 1, &p, 1, vDSP_Length(n))
            
            rsold = rsnew
        }
        
        throw SolverError.maxIterationsReached
    }
    
    private func solveGPU(A: SparseMatrix, b: [Float], device: MTLDevice, commandQueue: MTLCommandQueue) async throws -> [Float] {
        // Create buffers
        guard let xBuffer = device.makeBuffer(length: b.count * MemoryLayout<Float>.size,
                                            options: .storageModeShared),
              let rBuffer = device.makeBuffer(bytes: b,
                                            length: b.count * MemoryLayout<Float>.size,
                                            options: .storageModeShared),
              let pBuffer = device.makeBuffer(bytes: b,
                                            length: b.count * MemoryLayout<Float>.size,
                                            options: .storageModeShared),
              let ApBuffer = device.makeBuffer(length: b.count * MemoryLayout<Float>.size,
                                             options: .storageModeShared),
              let scalarBuffer = device.makeBuffer(length: MemoryLayout<Float>.size * 4,
                                                 options: .storageModeShared) else {
            throw SolverError.bufferAllocationFailed
        }
        
        // Initialize solution
        let x = xBuffer.contents().assumingMemoryBound(to: Float.self)
        memset(x, 0, b.count * MemoryLayout<Float>.size)
        
        // Main iteration loop
        for iteration in 0..<maxIterations {
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw SolverError.commandBufferCreationFailed
            }
            
            // Compute matrix-vector product
            try A.multiplyGPU(vector: pBuffer,
                             result: ApBuffer,
                             commandBuffer: commandBuffer,
                             device: device)
            
            // Update solution and compute new residual
            try updateSolutionGPU(x: xBuffer,
                                r: rBuffer,
                                p: pBuffer,
                                Ap: ApBuffer,
                                scalars: scalarBuffer,
                                commandBuffer: commandBuffer,
                                device: device)
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            // Check convergence
            let scalars = scalarBuffer.contents().assumingMemoryBound(to: Float.self)
            if sqrt(scalars[1]) < tolerance { // scalars[1] contains rsnew
                return Array(UnsafeBufferPointer(start: x, count: b.count))
            }
        }
        
        throw SolverError.maxIterationsReached
    }
}

enum SolverError: Error {
    case maxIterationsReached
    case bufferAllocationFailed
    case commandBufferCreationFailed
    case kernelCreationFailed
}
