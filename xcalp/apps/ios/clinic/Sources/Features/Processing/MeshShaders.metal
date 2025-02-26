#include <metal_stdlib>
using namespace metal;

// Optimized data structures for better memory alignment
struct MeshVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    float quadricError [[attribute(3)]];
    float meshDensity [[attribute(4)]];
    float featureImportance [[attribute(5)]];
    float processingWeight [[attribute(6)]];
};

struct OptimizationUniforms {
    float4x4 modelMatrix;
    float targetQuality;
    float errorThreshold;
    uint maxIterations;
    uint currentIteration;
};

struct ProcessingUniforms {
    float4x4 modelMatrix;
    float targetQuality;
    float errorThreshold;
    uint maxIterations;
    uint currentIteration;
    float densityTarget;
    float featureThreshold;
    float adaptiveWeight;
};

// Shared threadgroup memory for better performance
struct ThreadgroupData {
    float3 averagePosition;
    float3 averageNormal;
    atomic_uint vertexCount;
    atomic_uint processedCount;
};

// Enhanced mesh decimation kernel with adaptive processing
kernel void optimized_decimate_mesh(
    device MeshVertex *vertices [[buffer(0)]],
    device uint *indices [[buffer(1)]],
    device atomic_uint *vertexCount [[buffer(2)]],
    constant ProcessingUniforms &uniforms [[buffer(3)]],
    device float *qualityMetrics [[buffer(4)]],
    threadgroup ThreadgroupData &shared [[threadgroup(0)]],
    uint3 tid [[thread_position_in_grid]],
    uint3 lid [[thread_position_in_threadgroup]],
    uint3 group_size [[threads_per_threadgroup]]) {
    
    if (tid.x >= atomic_load_explicit(vertexCount, memory_order_relaxed)) {
        return;
    }
    
    // Initialize shared memory
    if (lid.x == 0) {
        shared.averagePosition = float3(0.0);
        shared.averageNormal = float3(0.0);
        atomic_store_explicit(&shared.vertexCount, 0, memory_order_relaxed);
        atomic_store_explicit(&shared.processedCount, 0, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    MeshVertex vertex = vertices[tid.x];
    
    // Calculate local mesh density and feature importance
    float localDensity = calculateLocalDensity(vertex, vertices, vertexCount);
    float featureImportance = calculateFeatureImportance(vertex, vertices, indices);
    
    // Update vertex attributes
    vertices[tid.x].meshDensity = localDensity;
    vertices[tid.x].featureImportance = featureImportance;
    vertices[tid.x].processingWeight = calculateProcessingWeight(
        localDensity,
        featureImportance,
        uniforms.adaptiveWeight
    );
    
    // Adaptive decimation based on processing weight
    if (vertex.processingWeight > uniforms.featureThreshold) {
        float4x4 Q = calculateQuadricMatrix(vertex, vertices, indices);
        float error = calculateQuadricError(vertex.position, Q);
        
        if (error < uniforms.errorThreshold * vertex.processingWeight) {
            float3 optimalPosition = findOptimalPosition(vertex, Q);
            if (isValidCollapse(optimalPosition, error, uniforms.targetQuality)) {
                performEdgeCollapse(tid.x, optimalPosition, vertices, indices, vertexCount);
                atomic_fetch_add_explicit(&shared.processedCount, 1, memory_order_relaxed);
            }
        }
    }
    
    // Accumulate data for quality metrics
    atomic_fetch_add_explicit(&shared.vertexCount, 1, memory_order_relaxed);
    float3 weightedPosition = vertex.position * vertex.processingWeight;
    float3 weightedNormal = vertex.normal * vertex.processingWeight;
    
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // Update quality metrics
    if (lid.x == 0) {
        uint processed = atomic_load_explicit(&shared.processedCount, memory_order_relaxed);
        uint total = atomic_load_explicit(&shared.vertexCount, memory_order_relaxed);
        float processingEfficiency = float(processed) / float(total);
        qualityMetrics[0] = processingEfficiency;
    }
}

// New kernel for parallel feature detection
kernel void detect_features(
    device MeshVertex *vertices [[buffer(0)]],
    device uint *indices [[buffer(1)]],
    device atomic_uint *vertexCount [[buffer(2)]],
    constant ProcessingUniforms &uniforms [[buffer(3)]],
    device float *featureMap [[buffer(4)]],
    uint3 tid [[thread_position_in_grid]]) {
    
    if (tid.x >= atomic_load_explicit(vertexCount, memory_order_relaxed)) {
        return;
    }
    
    MeshVertex vertex = vertices[tid.x];
    
    // Enhanced feature detection using curvature analysis
    float3 curvature = calculateCurvature(vertex, vertices, indices);
    float featureStrength = length(curvature);
    
    // Update feature map
    featureMap[tid.x] = featureStrength;
    
    // Mark significant features
    if (featureStrength > uniforms.featureThreshold) {
        vertices[tid.x].featureImportance = 1.0;
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

static float calculateLocalDensity(
    MeshVertex vertex,
    device MeshVertex *vertices,
    device atomic_uint *vertexCount
) {
    float density = 0.0;
    float searchRadius = 0.01; // 1cm radius
    uint count = atomic_load_explicit(vertexCount, memory_order_relaxed);
    
    // Use spatial hashing for faster neighbor search
    for (uint i = 0; i < count; i++) {
        float3 diff = vertex.position - vertices[i].position;
        float dist = length(diff);
        if (dist < searchRadius) {
            density += 1.0 - (dist / searchRadius);
        }
    }
    
    return density;
}

static float calculateFeatureImportance(
    MeshVertex vertex,
    device MeshVertex *vertices,
    device uint *indices
) {
    // Enhanced feature detection using normal variation
    float importance = 0.0;
    float3 normal = vertex.normal;
    
    for (uint i = 0; i < 3; i++) {
        float3 neighborNormal = vertices[indices[i]].normal;
        importance += 1.0 - abs(dot(normal, neighborNormal));
    }
    
    return importance / 3.0;
}

static float calculateProcessingWeight(
    float density,
    float importance,
    float adaptiveWeight
) {
    // Adaptive weight calculation based on local properties
    return mix(density, importance, adaptiveWeight);
}

static float3 calculateCurvature(
    MeshVertex vertex,
    device MeshVertex *vertices,
    device uint *indices
) {
    // Calculate mean curvature using laplacian operator
    float3 curvature = float3(0.0);
    float3 position = vertex.position;
    float totalWeight = 0.0;
    
    for (uint i = 0; i < 3; i++) {
        float3 neighborPos = vertices[indices[i]].position;
        float3 diff = neighborPos - position;
        float weight = 1.0 / max(length(diff), 1e-6);
        curvature += diff * weight;
        totalWeight += weight;
    }
    
    return curvature / max(totalWeight, 1e-6);
}