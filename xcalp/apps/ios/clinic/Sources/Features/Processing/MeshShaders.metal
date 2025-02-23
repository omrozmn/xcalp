#include <metal_stdlib>
using namespace metal;

struct MeshVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float quadricError [[attribute(3)]];
};

struct OptimizationUniforms {
    float4x4 modelMatrix;
    float targetQuality;
    float errorThreshold;
    uint maxIterations;
    uint currentIteration;
};

// Compute shader for mesh decimation using quadric error metrics
kernel void decimate_mesh(device MeshVertex *vertices [[buffer(0)]],
                         device uint *indices [[buffer(1)]],
                         device atomic_uint *vertexCount [[buffer(2)]],
                         constant OptimizationUniforms &uniforms [[buffer(3)]],
                         uint3 tid [[thread_position_in_grid]]) {
    if (tid.x >= atomic_load_explicit(vertexCount, memory_order_relaxed)) {
        return;
    }
    
    MeshVertex vertex = vertices[tid.x];
    float4x4 Q = calculateQuadricMatrix(vertex, vertices, indices);
    float error = calculateQuadricError(vertex.position, Q);
    
    // Update vertex quadric error
    vertices[tid.x].quadricError = error;
    
    // Attempt vertex pair collapse if error is below threshold
    if (error < uniforms.errorThreshold && 
        uniforms.currentIteration < uniforms.maxIterations) {
        float3 optimalPosition = findOptimalPosition(vertex, Q);
        if (isValidCollapse(optimalPosition, error, uniforms.targetQuality)) {
            performEdgeCollapse(tid.x, optimalPosition, vertices, indices, vertexCount);
        }
    }
}

// Kernel for normal recalculation after mesh modification
kernel void recalculate_normals(device MeshVertex *vertices [[buffer(0)]],
                              device uint *indices [[buffer(1)]],
                              device atomic_uint *vertexCount [[buffer(2)]],
                              uint3 tid [[thread_position_in_grid]]) {
    if (tid.x >= atomic_load_explicit(vertexCount, memory_order_relaxed)) {
        return;
    }
    
    float3 normal = float3(0.0);
    uint adjacentFaces = 0;
    
    // Calculate vertex normal by averaging adjacent face normals
    for (uint i = 0; i < atomic_load_explicit(vertexCount, memory_order_relaxed); i += 3) {
        if (indices[i] == tid.x || indices[i+1] == tid.x || indices[i+2] == tid.x) {
            float3 v0 = vertices[indices[i]].position;
            float3 v1 = vertices[indices[i+1]].position;
            float3 v2 = vertices[indices[i+2]].position;
            
            float3 faceNormal = normalize(cross(v1 - v0, v2 - v0));
            normal += faceNormal;
            adjacentFaces++;
        }
    }
    
    if (adjacentFaces > 0) {
        vertices[tid.x].normal = normalize(normal / float(adjacentFaces));
    }
}

// Helper functions
static float4x4 calculateQuadricMatrix(MeshVertex vertex,
                                     device MeshVertex *vertices,
                                     device uint *indices) {
    float4x4 Q = float4x4(0.0);
    float3 p = vertex.position;
    float3 n = vertex.normal;
    
    // Fundamental error quadric for vertex
    float4 plane = float4(n, -dot(n, p));
    Q += outer_product(plane, plane);
    
    return Q;
}

static float calculateQuadricError(float3 position, float4x4 Q) {
    float4 p = float4(position, 1.0);
    return dot(p, Q * p);
}

static float3 findOptimalPosition(MeshVertex vertex, float4x4 Q) {
    // Solve for optimal position using quadric error metrics
    float3x3 A = float3x3(Q[0].xyz, Q[1].xyz, Q[2].xyz);
    float3 b = float3(-Q[0].w, -Q[1].w, -Q[2].w);
    
    float det = determinant(A);
    if (abs(det) < 1e-6) {
        return vertex.position;
    }
    
    return solve3x3(A, b);
}

static bool isValidCollapse(float3 position, float error, float qualityThreshold) {
    return error < qualityThreshold && !any(isnan(position));
}

static void performEdgeCollapse(uint vertexIndex,
                              float3 newPosition,
                              device MeshVertex *vertices,
                              device uint *indices,
                              device atomic_uint *vertexCount) {
    vertices[vertexIndex].position = newPosition;
    atomic_fetch_sub_explicit(vertexCount, 1, memory_order_relaxed);
}

static float3 solve3x3(float3x3 A, float3 b) {
    float det = determinant(A);
    if (abs(det) < 1e-6) {
        return float3(0.0);
    }
    
    float3x3 invA = float3x3(
        cross(A[1], A[2]) / det,
        cross(A[2], A[0]) / det,
        cross(A[0], A[1]) / det
    );
    
    return invA * b;
}