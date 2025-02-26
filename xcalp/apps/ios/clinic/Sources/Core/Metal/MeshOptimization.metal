#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[position]];
    float3 normal;
};

struct OptimizationParams {
    float smoothingFactor;
    float featureThreshold;
    int iterationCount;
    bool preserveFeatures;
};

// Calculate vertex curvature for feature preservation
float calculateCurvature(float3 position, float3 normal, const device Vertex* vertices, uint vertexCount) {
    float curvature = 0.0;
    float weight = 0.0;
    
    for (uint i = 0; i < vertexCount; i++) {
        float3 diff = vertices[i].position - position;
        float dist = length(diff);
        
        if (dist > 0.0001 && dist < 0.1) { // Ignore self and far vertices
            float w = 1.0 / dist;
            curvature += w * abs(dot(normalize(diff), normal));
            weight += w;
        }
    }
    
    return weight > 0.0 ? curvature / weight : 0.0;
}

// Smooth vertices while preserving features
kernel void optimizeMeshKernel(
    device Vertex* vertices [[buffer(0)]],
    device const uint* indices [[buffer(1)]],
    constant OptimizationParams& params [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertices.arrayLength()) return;
    
    Vertex vertex = vertices[vid];
    float3 smoothedPosition = float3(0);
    float3 smoothedNormal = float3(0);
    float totalWeight = 0.0;
    
    // Calculate vertex curvature for feature detection
    float curvature = calculateCurvature(
        vertex.position,
        vertex.normal,
        vertices,
        vertices.arrayLength()
    );
    
    // Adjust smoothing based on curvature
    float adaptiveSmoothingFactor = params.preserveFeatures ?
        params.smoothingFactor * (1.0 - min(curvature / params.featureThreshold, 1.0)) :
        params.smoothingFactor;
    
    // Accumulate weighted contributions from neighbors
    for (uint i = 0; i < vertices.arrayLength(); i++) {
        if (i == vid) continue;
        
        float3 diff = vertices[i].position - vertex.position;
        float dist = length(diff);
        
        if (dist < 0.1) { // Consider only close neighbors
            float weight = 1.0 / (1.0 + dist);
            
            smoothedPosition += weight * vertices[i].position;
            smoothedNormal += weight * vertices[i].normal;
            totalWeight += weight;
        }
    }
    
    if (totalWeight > 0.0) {
        // Apply smoothing with feature preservation
        smoothedPosition /= totalWeight;
        smoothedNormal = normalize(smoothedNormal);
        
        vertices[vid].position = mix(
            vertex.position,
            smoothedPosition,
            adaptiveSmoothingFactor
        );
        
        vertices[vid].normal = normalize(mix(
            vertex.normal,
            smoothedNormal,
            adaptiveSmoothingFactor
        ));
    }
}

// Calculate mesh quality metrics
kernel void calculateMeshQualityKernel(
    device const Vertex* vertices [[buffer(0)]],
    device const uint3* triangles [[buffer(1)]],
    device float4* qualityMetrics [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= triangles.arrayLength()) return;
    
    uint3 triangle = triangles[tid];
    float3 v0 = vertices[triangle.x].position;
    float3 v1 = vertices[triangle.y].position;
    float3 v2 = vertices[triangle.z].position;
    
    // Calculate edge lengths
    float3 edges = float3(
        length(v1 - v0),
        length(v2 - v1),
        length(v0 - v2)
    );
    
    // Calculate angles
    float3 angles;
    angles.x = acos(dot(normalize(v1 - v0), normalize(v2 - v0)));
    angles.y = acos(dot(normalize(v2 - v1), normalize(v0 - v1)));
    angles.z = acos(dot(normalize(v0 - v2), normalize(v1 - v2)));
    
    // Convert to degrees
    angles *= 180.0 / M_PI_F;
    
    // Calculate aspect ratio
    float maxEdge = max(max(edges.x, edges.y), edges.z);
    float minEdge = min(min(edges.x, edges.y), edges.z);
    float aspectRatio = maxEdge / minEdge;
    
    // Store quality metrics for this triangle
    qualityMetrics[tid] = float4(
        aspectRatio,
        min(min(angles.x, angles.y), angles.z),  // min angle
        max(max(angles.x, angles.y), angles.z),  // max angle
        0.0  // reserved
    );
}