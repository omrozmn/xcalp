// Kernel functions for mesh optimization
#include <metal_stdlib>
using namespace metal;

// Data structures
struct Vertex {
    float3 position [[position]];
    float3 normal;
    float confidence;
};

struct OptimizationParams {
    float smoothingFactor;
    float featureThreshold;
    float edgePreservationWeight;
    int neighborhoodSize;
};

// MARK: - Mesh Smoothing

kernel void laplacianSmoothing(
    device Vertex *vertices [[buffer(0)]],
    device const uint *indices [[buffer(1)]],
    device const OptimizationParams &params [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    const float3 currentPos = vertices[vid].position;
    const float3 currentNormal = vertices[vid].normal;
    
    // Find neighbors through index buffer
    float3 centroid = float3(0.0);
    float3 avgNormal = float3(0.0);
    int neighborCount = 0;
    
    // Iterate through triangles to find connected vertices
    for (uint i = 0; i < params.neighborhoodSize * 3; i += 3) {
        for (uint j = 0; j < 3; j++) {
            if (indices[i + j] == vid) {
                // Get other two vertices of the triangle
                uint v1 = indices[i + (j + 1) % 3];
                uint v2 = indices[i + (j + 2) % 3];
                
                centroid += vertices[v1].position + vertices[v2].position;
                avgNormal += vertices[v1].normal + vertices[v2].normal;
                neighborCount += 2;
            }
        }
    }
    
    if (neighborCount > 0) {
        centroid /= float(neighborCount);
        avgNormal = normalize(avgNormal / float(neighborCount));
        
        // Calculate feature intensity
        float featureIntensity = 1.0 - abs(dot(currentNormal, avgNormal));
        float adaptiveWeight = params.smoothingFactor * (1.0 - featureIntensity * params.edgePreservationWeight);
        
        // Update position with feature-preserving smoothing
        if (featureIntensity < params.featureThreshold) {
            vertices[vid].position = mix(currentPos, centroid, adaptiveWeight);
            vertices[vid].normal = normalize(mix(currentNormal, avgNormal, adaptiveWeight));
        }
    }
}

// MARK: - Feature Detection

kernel void detectFeatures(
    device const Vertex *vertices [[buffer(0)]],
    device float *featureScores [[buffer(1)]],
    device const OptimizationParams &params [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    const float3 position = vertices[vid].position;
    const float3 normal = vertices[vid].normal;
    
    float featureScore = 0.0;
    int neighborCount = 0;
    
    // Analyze local neighborhood
    for (uint i = 0; i < params.neighborhoodSize; i++) {
        if (i != vid) {
            float3 neighborPos = vertices[i].position;
            float3 neighborNormal = vertices[i].normal;
            
            float3 diff = neighborPos - position;
            float distance = length(diff);
            
            if (distance < 0.1) { // Local neighborhood threshold
                float normalDiff = 1.0 - abs(dot(normal, neighborNormal));
                float weight = exp(-distance * 10.0); // Distance-based weight
                featureScore += normalDiff * weight;
                neighborCount++;
            }
        }
    }
    
    // Normalize feature score
    featureScores[vid] = neighborCount > 0 ? featureScore / float(neighborCount) : 0.0;
}

// MARK: - Mesh Decimation

kernel void markVerticesForDecimation(
    device const Vertex *vertices [[buffer(0)]],
    device const float *featureScores [[buffer(1)]],
    device bool *retainVertex [[buffer(2)]],
    device const OptimizationParams &params [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    float featureScore = featureScores[vid];
    bool isFeature = featureScore > params.featureThreshold;
    
    // Calculate local density
    float localDensity = 0.0;
    int neighborCount = 0;
    
    for (uint i = 0; i < params.neighborhoodSize; i++) {
        if (i != vid) {
            float3 diff = vertices[i].position - vertices[vid].position;
            float distance = length(diff);
            
            if (distance < 0.1) {
                localDensity += 1.0;
                neighborCount++;
            }
        }
    }
    
    localDensity = neighborCount > 0 ? localDensity / float(neighborCount) : 0.0;
    
    // Retain vertices that are either features or in low-density regions
    retainVertex[vid] = isFeature || localDensity < 0.5;
}

// MARK: - Normal Recalculation

kernel void recalculateNormals(
    device Vertex *vertices [[buffer(0)]],
    device const uint *indices [[buffer(1)]],
    uint tid [[thread_position_in_grid]]
) {
    // Process one triangle at a time
    uint i0 = indices[tid * 3];
    uint i1 = indices[tid * 3 + 1];
    uint i2 = indices[tid * 3 + 2];
    
    float3 v0 = vertices[i0].position;
    float3 v1 = vertices[i1].position;
    float3 v2 = vertices[i2].position;
    
    // Calculate triangle normal
    float3 edge1 = v1 - v0;
    float3 edge2 = v2 - v0;
    float3 triangleNormal = normalize(cross(edge1, edge2));
    
    // Contribute to vertex normals (atomic for thread safety)
    atomic_store_explicit((device atomic_float*)&vertices[i0].normal.x, triangleNormal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i0].normal.y, triangleNormal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i0].normal.z, triangleNormal.z, memory_order_relaxed);
    
    atomic_store_explicit((device atomic_float*)&vertices[i1].normal.x, triangleNormal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i1].normal.y, triangleNormal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i1].normal.z, triangleNormal.z, memory_order_relaxed);
    
    atomic_store_explicit((device atomic_float*)&vertices[i2].normal.x, triangleNormal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i2].normal.y, triangleNormal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&vertices[i2].normal.z, triangleNormal.z, memory_order_relaxed);
}