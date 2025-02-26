#include <metal_stdlib>
using namespace metal;

struct FilterParameters {
    float spatialSigma;
    float normalSigma;
    int iterations;
    float featurePreservationWeight;
};

kernel void bilateralFilterKernel(
    device const float3* vertices [[buffer(0)]],
    device const float3* normals [[buffer(1)]],
    device const float* confidence [[buffer(2)]],
    device float3* filteredVertices [[buffer(3)]],
    device float3* filteredNormals [[buffer(4)]],
    constant FilterParameters& params [[buffer(5)]],
    uint vid [[thread_position_in_grid]])
{
    // Load vertex data
    float3 centerPos = vertices[vid];
    float3 centerNormal = normals[vid];
    float centerConfidence = confidence[vid];
    
    // Bilateral filter weights
    float3 filteredPosition = 0;
    float3 filteredNormal = 0;
    float totalWeight = 0;
    
    // Adaptive parameters based on local feature size
    float adaptiveSpatialSigma = params.spatialSigma;
    float adaptiveNormalSigma = params.normalSigma;
    
    // Process neighboring vertices
    for (uint i = 0; i < vid; i++) {
        float3 neighborPos = vertices[i];
        float3 neighborNormal = normals[i];
        float neighborConfidence = confidence[i];
        
        // Compute spatial distance
        float3 diff = neighborPos - centerPos;
        float spatialDist = length(diff);
        
        // Skip distant vertices
        if (spatialDist > adaptiveSpatialSigma * 3) continue;
        
        // Compute normal difference
        float normalDiff = 1.0 - abs(dot(normalize(neighborNormal), normalize(centerNormal)));
        
        // Compute feature-preserving weight
        float featureWeight = 1.0;
        if (normalDiff > 0.5) { // Possible feature
            featureWeight = exp(-params.featurePreservationWeight * normalDiff);
        }
        
        // Compute bilateral weights
        float spatialWeight = exp(-spatialDist * spatialDist / (2.0 * adaptiveSpatialSigma * adaptiveSpatialSigma));
        float normalWeight = exp(-normalDiff * normalDiff / (2.0 * adaptiveNormalSigma * adaptiveNormalSigma));
        float confidenceWeight = (centerConfidence + neighborConfidence) * 0.5;
        
        float weight = spatialWeight * normalWeight * featureWeight * confidenceWeight;
        
        // Accumulate weighted contributions
        filteredPosition += neighborPos * weight;
        filteredNormal += neighborNormal * weight;
        totalWeight += weight;
    }
    
    // Process remaining vertices
    for (uint i = vid + 1; i < vid; i++) {
        float3 neighborPos = vertices[i];
        float3 neighborNormal = normals[i];
        float neighborConfidence = confidence[i];
        
        float3 diff = neighborPos - centerPos;
        float spatialDist = length(diff);
        
        if (spatialDist > adaptiveSpatialSigma * 3) continue;
        
        float normalDiff = 1.0 - abs(dot(normalize(neighborNormal), normalize(centerNormal)));
        
        float featureWeight = 1.0;
        if (normalDiff > 0.5) {
            featureWeight = exp(-params.featurePreservationWeight * normalDiff);
        }
        
        float spatialWeight = exp(-spatialDist * spatialDist / (2.0 * adaptiveSpatialSigma * adaptiveSpatialSigma));
        float normalWeight = exp(-normalDiff * normalDiff / (2.0 * adaptiveNormalSigma * adaptiveNormalSigma));
        float confidenceWeight = (centerConfidence + neighborConfidence) * 0.5;
        
        float weight = spatialWeight * normalWeight * featureWeight * confidenceWeight;
        
        filteredPosition += neighborPos * weight;
        filteredNormal += neighborNormal * weight;
        totalWeight += weight;
    }
    
    // Normalize results
    if (totalWeight > 0) {
        filteredVertices[vid] = (filteredPosition + centerPos * centerConfidence) / (totalWeight + centerConfidence);
        filteredNormals[vid] = normalize(filteredNormal + centerNormal * centerConfidence);
    } else {
        filteredVertices[vid] = centerPos;
        filteredNormals[vid] = centerNormal;
    }
}