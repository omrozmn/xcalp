#include <metal_stdlib>
using namespace metal;

struct FeatureDetectionParams {
    float confidenceThreshold;
    float distanceThreshold;
    int maxNeighbors;
    float curvatureWeight;
    float normalConsistencyWeight;
};

struct Vertex {
    float3 position [[position]];
    float3 normal;
};

struct FeatureData {
    float3 position;
    float confidence;
    float curvature;
    float saliency;
};

// Helper functions for feature detection
float calculateCurvature(
    float3 vertex,
    float3 normal,
    device const Vertex* vertices,
    uint vertexCount,
    float radius
) {
    float3 mean = 0;
    float3 meanNormal = 0;
    int count = 0;
    
    for (uint i = 0; i < vertexCount; i++) {
        float3 diff = vertices[i].position - vertex;
        float dist = length(diff);
        
        if (dist > 0 && dist < radius) {
            mean += vertices[i].position;
            meanNormal += vertices[i].normal;
            count++;
        }
    }
    
    if (count == 0) return 0;
    
    mean /= count;
    meanNormal = normalize(meanNormal / count);
    
    // Calculate variation from mean plane
    float variation = 0;
    for (uint i = 0; i < vertexCount; i++) {
        float3 diff = vertices[i].position - vertex;
        float dist = length(diff);
        
        if (dist > 0 && dist < radius) {
            float planeDist = abs(dot(diff, meanNormal));
            variation += planeDist * planeDist;
        }
    }
    
    return count > 0 ? sqrt(variation / count) : 0;
}

float calculateSaliency(
    float3 position,
    float3 normal,
    device const Vertex* vertices,
    device const float3* normals,
    uint vertexCount,
    float radius
) {
    float saliency = 0;
    int count = 0;
    
    for (uint i = 0; i < vertexCount; i++) {
        float3 diff = vertices[i].position - position;
        float dist = length(diff);
        
        if (dist > 0 && dist < radius) {
            float normalDiff = 1.0 - abs(dot(normal, normals[i]));
            float weight = exp(-dist * dist / (radius * radius));
            saliency += normalDiff * weight;
            count++;
        }
    }
    
    return count > 0 ? saliency / count : 0;
}

kernel void detectFeatures(
    device const Vertex* vertices [[buffer(0)]],
    device FeatureData* features [[buffer(1)]],
    device const FeatureDetectionParams& params [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    const float3 position = vertices[vid].position;
    const float3 normal = vertices[vid].normal;
    
    // Calculate local geometric properties
    float curvature = calculateCurvature(
        position,
        normal,
        vertices,
        params.maxNeighbors,
        params.distanceThreshold
    );
    
    float saliency = calculateSaliency(
        position,
        normal,
        vertices,
        vertices[vid].normal,
        params.maxNeighbors,
        params.distanceThreshold
    );
    
    // Combine metrics for final confidence score
    float confidence = params.curvatureWeight * curvature +
                      params.normalConsistencyWeight * saliency;
    
    // Store feature data
    features[vid].position = position;
    features[vid].confidence = confidence > params.confidenceThreshold ? confidence : 0;
    features[vid].curvature = curvature;
    features[vid].saliency = saliency;
}

kernel void classifyFeatures(
    device const FeatureData* features [[buffer(0)]],
    device int* featureTypes [[buffer(1)]],
    device const FeatureDetectionParams& params [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    const FeatureData feature = features[vid];
    
    // Classify feature type based on geometric properties
    if (feature.confidence < params.confidenceThreshold) {
        featureTypes[vid] = 0; // Not a feature
    } else if (feature.curvature > 0.8) {
        featureTypes[vid] = 1; // Corner
    } else if (feature.saliency > 0.6) {
        featureTypes[vid] = 2; // Edge
    } else {
        featureTypes[vid] = 3; // Surface feature
    }
}