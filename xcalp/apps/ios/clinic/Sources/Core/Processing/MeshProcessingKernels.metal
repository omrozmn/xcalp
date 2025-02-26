#include <metal_stdlib>
using namespace metal;

struct MeshVertex {
    float3 position;
    float3 normal;
    float confidence;
};

struct FeaturePoint {
    float3 position;
    float3 normal;
    float strength;
};

// Feature detection kernel with optimized spatial search
kernel void detectMeshFeatures(
    device const MeshVertex* vertices [[buffer(0)]],
    device FeaturePoint* features [[buffer(1)]],
    device atomic_uint* featureCount [[buffer(2)]],
    constant float& featureThreshold [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    MeshVertex vertex = vertices[vid];
    float featureScore = 0.0;
    
    // Local neighborhood analysis for feature detection
    for (uint i = max(0, int(vid) - 8); i < min(vid + 9, vid); i++) {
        if (i == vid) continue;
        
        MeshVertex neighbor = vertices[i];
        float3 diff = neighbor.position - vertex.position;
        float dist = length(diff);
        
        if (dist < 0.01) { // 1cm radius
            // Calculate geometric features
            float normalAlignment = dot(normalize(neighbor.normal), normalize(vertex.normal));
            float curvature = 1.0 - normalAlignment;
            
            // Weight by distance and confidence
            float weight = exp(-dist * dist * 100.0) * neighbor.confidence;
            featureScore += curvature * weight;
        }
    }
    
    // Feature detection threshold check
    if (featureScore > featureThreshold) {
        uint featureIndex = atomic_fetch_add_explicit(featureCount, 1, memory_order_relaxed);
        features[featureIndex].position = vertex.position;
        features[featureIndex].normal = vertex.normal;
        features[featureIndex].strength = featureScore;
    }
}

// Optimized mesh merging kernel
kernel void mergeMeshData(
    device const MeshVertex* lidarVertices [[buffer(0)]],
    device const MeshVertex* photoVertices [[buffer(1)]],
    device MeshVertex* mergedVertices [[buffer(2)]],
    constant uint& lidarCount [[buffer(3)]],
    constant uint& photoCount [[buffer(4)]],
    constant float& mergeThreshold [[buffer(5)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= lidarCount) return;
    
    MeshVertex lidarVertex = lidarVertices[vid];
    float3 mergedPosition = lidarVertex.position;
    float3 mergedNormal = lidarVertex.normal;
    float mergedConfidence = lidarVertex.confidence;
    float totalWeight = lidarVertex.confidence;
    
    // Find and merge with nearby photogrammetry vertices
    for (uint i = 0; i < photoCount; i++) {
        MeshVertex photoVertex = photoVertices[i];
        float3 diff = photoVertex.position - lidarVertex.position;
        float dist = length(diff);
        
        if (dist < mergeThreshold) {
            float weight = photoVertex.confidence * exp(-dist * dist / (mergeThreshold * mergeThreshold));
            
            mergedPosition += photoVertex.position * weight;
            mergedNormal += photoVertex.normal * weight;
            mergedConfidence = max(mergedConfidence, photoVertex.confidence);
            totalWeight += weight;
        }
    }
    
    // Normalize merged results
    if (totalWeight > 0) {
        mergedVertices[vid].position = mergedPosition / totalWeight;
        mergedVertices[vid].normal = normalize(mergedNormal);
        mergedVertices[vid].confidence = mergedConfidence;
    } else {
        mergedVertices[vid] = lidarVertex;
    }
}

// Curvature estimation kernel
kernel void calculateCurvature(
    device const MeshVertex* vertices [[buffer(0)]],
    device float* curvatures [[buffer(1)]],
    constant uint& vertexCount [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertexCount) return;
    
    MeshVertex vertex = vertices[vid];
    float3x3 covariance = float3x3(0.0);
    float totalWeight = 0.0;
    
    // Compute weighted covariance matrix
    for (uint i = 0; i < vertexCount; i++) {
        if (i == vid) continue;
        
        MeshVertex neighbor = vertices[i];
        float3 diff = neighbor.position - vertex.position;
        float dist = length(diff);
        
        if (dist < 0.01) {
            float weight = exp(-dist * dist * 100.0);
            diff = normalize(diff);
            
            covariance += weight * float3x3(
                diff.x * diff.x, diff.x * diff.y, diff.x * diff.z,
                diff.y * diff.x, diff.y * diff.y, diff.y * diff.z,
                diff.z * diff.x, diff.z * diff.y, diff.z * diff.z
            );
            
            totalWeight += weight;
        }
    }
    
    if (totalWeight > 0) {
        covariance /= totalWeight;
        
        // Estimate curvature using eigenvalues
        float trace = covariance[0][0] + covariance[1][1] + covariance[2][2];
        float trace2 = covariance[0][0] * covariance[0][0] +
                      covariance[1][1] * covariance[1][1] +
                      covariance[2][2] * covariance[2][2] +
                      2.0 * (covariance[0][1] * covariance[1][0] +
                            covariance[0][2] * covariance[2][0] +
                            covariance[1][2] * covariance[2][1]);
        
        float curvature = trace * trace - trace2;
        curvatures[vid] = curvature;
    } else {
        curvatures[vid] = 0.0;
    }
}