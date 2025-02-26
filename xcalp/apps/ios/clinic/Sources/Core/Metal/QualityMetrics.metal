#include <metal_stdlib>
using namespace metal;

struct SurfaceMetrics {
    float completeness;
    float continuity;
    float normalConsistency;
};

kernel void calculateQualityMetrics(
    device const float3* points [[ buffer(0) ]],
    device const float3* normals [[ buffer(1) ]],
    device SurfaceMetrics* metrics [[ buffer(2) ]],
    uint tid [[ thread_position_in_grid ]],
    uint threads [[ threads_per_grid ]]
) {
    if (tid >= threads) return;
    
    const float searchRadius = 0.05; // 5cm radius for local analysis
    const float minNeighbors = 5.0;
    float localCompleteness = 0.0;
    float localContinuity = 0.0;
    float localNormalConsistency = 0.0;
    int neighbors = 0;
    
    // Current point and normal
    float3 center = points[tid];
    float3 centerNormal = normals[tid];
    
    // Analyze local neighborhood
    for (uint i = 0; i < threads; i++) {
        if (i == tid) continue;
        
        float3 diff = points[i] - center;
        float dist = length(diff);
        
        if (dist < searchRadius) {
            neighbors++;
            
            // Track surface continuity using distance distribution
            localContinuity += 1.0 - (dist / searchRadius);
            
            // Evaluate normal consistency
            float normalAlignment = dot(normalize(normals[i]), centerNormal);
            localNormalConsistency += normalAlignment;
            
            // Track gaps for completeness analysis
            float maxGap = 0.0;
            for (uint j = 0; j < threads; j++) {
                if (j == i || j == tid) continue;
                float3 otherDiff = points[j] - center;
                if (length(otherDiff) < searchRadius) {
                    float gap = length(normalize(diff) - normalize(otherDiff));
                    maxGap = max(maxGap, gap);
                }
            }
            localCompleteness = 1.0 - min(1.0, maxGap / (2.0 * M_PI_F));
        }
    }
    
    // Calculate final metrics
    if (neighbors > 0) {
        float coverage = float(neighbors) / minNeighbors;
        coverage = min(1.0, coverage);
        
        metrics[tid].completeness = localCompleteness * coverage;
        metrics[tid].continuity = localContinuity / float(neighbors);
        metrics[tid].normalConsistency = localNormalConsistency / float(neighbors);
    } else {
        metrics[tid].completeness = 0.0;
        metrics[tid].continuity = 0.0;
        metrics[tid].normalConsistency = 0.0;
    }
}

kernel void detectFeatures(
    device const float3* points [[ buffer(0) ]],
    device const float3* normals [[ buffer(1) ]],
    device float* featureScores [[ buffer(2) ]],
    constant float& threshold [[ buffer(3) ]],
    uint tid [[ thread_position_in_grid ]],
    uint threads [[ threads_per_grid ]]
) {
    if (tid >= threads) return;
    
    float3 point = points[tid];
    float3 normal = normals[tid];
    float featureScore = 0.0;
    
    // Calculate local curvature
    float curvature = 0.0;
    int neighbors = 0;
    
    for (uint i = 0; i < threads; i++) {
        if (i == tid) continue;
        
        float3 diff = points[i] - point;
        float dist = length(diff);
        
        if (dist < threshold) {
            float3 neighborNormal = normals[i];
            float normalDiff = 1.0 - dot(normal, neighborNormal);
            curvature += normalDiff;
            neighbors++;
        }
    }
    
    if (neighbors > 0) {
        curvature /= float(neighbors);
        
        // High curvature indicates potential feature
        featureScore = curvature > 0.3 ? 1.0 : 0.0;
    }
    
    featureScores[tid] = featureScore;
}