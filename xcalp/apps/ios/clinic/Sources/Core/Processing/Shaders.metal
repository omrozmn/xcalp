#include <metal_stdlib>
using namespace metal;

struct Point {
    float3 position;
    float3 normal;
    float confidence;
};

kernel void processPointsKernel(device const Point* input [[ buffer(0) ]],
                              device Point* output [[ buffer(1) ]],
                              uint id [[ thread_position_in_grid ]]) {
    // Copy input point
    Point point = input[id];
    
    // Apply processing based on confidence
    if (point.confidence < 0.5) {
        // Low confidence points get more aggressive processing
        point.position = round(point.position * 1000) / 1000; // Round to nearest mm
        point.normal = normalize(point.normal);
        point.confidence = max(point.confidence, 0.1f); // Enforce minimum confidence
    } else {
        // High confidence points get lighter processing
        point.normal = normalize(point.normal);
    }
    
    // Store processed point
    output[id] = point;
}

kernel void denoisePointsKernel(device const Point* input [[ buffer(0) ]],
                              device Point* output [[ buffer(1) ]],
                              device const float* parameters [[ buffer(2) ]],
                              uint id [[ thread_position_in_grid ]]) {
    const float radius = parameters[0];
    const float sigmaS = parameters[1];
    const float sigmaR = parameters[2];
    
    Point centerPoint = input[id];
    float3 filtered_position = 0;
    float3 filtered_normal = 0;
    float weight_sum = 0;
    
    // Bilateral filter implementation
    for (uint i = max(0, int(id) - 10); i < min(id + 11, id); i++) {
        Point neighbor = input[i];
        
        float spatial_dist = length(neighbor.position - centerPoint.position);
        if (spatial_dist > radius) continue;
        
        float range_dist = abs(neighbor.confidence - centerPoint.confidence);
        
        float weight = exp(-spatial_dist * spatial_dist / (2 * sigmaS * sigmaS)) *
                      exp(-range_dist * range_dist / (2 * sigmaR * sigmaR));
        
        filtered_position += neighbor.position * weight;
        filtered_normal += neighbor.normal * weight;
        weight_sum += weight;
    }
    
    if (weight_sum > 0) {
        output[id].position = filtered_position / weight_sum;
        output[id].normal = normalize(filtered_normal / weight_sum);
        output[id].confidence = centerPoint.confidence;
    } else {
        output[id] = centerPoint;
    }
}

kernel void calculatePointDensityKernel(device const Point* points [[ buffer(0) ]],
                                      device float* density [[ buffer(1) ]],
                                      device const float* parameters [[ buffer(2) ]],
                                      uint id [[ thread_position_in_grid ]]) {
    const float radius = parameters[0];
    Point centerPoint = points[id];
    int neighborCount = 0;
    
    // Count points within radius
    for (uint i = 0; i < id; i++) {
        float dist = length(points[i].position - centerPoint.position);
        if (dist <= radius) {
            neighborCount++;
        }
    }
    
    // Calculate density (points per cubic meter)
    float volume = 4.0f/3.0f * M_PI_F * radius * radius * radius;
    density[id] = float(neighborCount) / volume;
}

// Add quality assessment kernels
kernel void calculateQualityMetricsKernel(
    device const Point* points [[buffer(0)]],
    device float* qualityScores [[buffer(1)]],
    device const float* parameters [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    const float searchRadius = parameters[0];
    Point centerPoint = points[id];
    
    // Initialize quality metrics
    float localDensity = 0;
    float normalConsistency = 0;
    float depthContinuity = 0;
    int neighborCount = 0;
    
    // Calculate local quality metrics
    for (uint i = 0; i < id; i++) {
        float3 diff = points[i].position - centerPoint.position;
        float dist = length(diff);
        
        if (dist < searchRadius) {
            // Contribute to local density
            localDensity += 1.0;
            
            // Normal consistency
            float normalAlignment = dot(normalize(points[i].normal), normalize(centerPoint.normal));
            normalConsistency += normalAlignment;
            
            // Depth continuity
            float depthDiff = abs(points[i].position.z - centerPoint.position.z);
            depthContinuity += 1.0 / (1.0 + depthDiff);
            
            neighborCount++;
        }
    }
    
    // Normalize metrics
    if (neighborCount > 0) {
        localDensity /= (M_PI_F * searchRadius * searchRadius); // points per unit area
        normalConsistency /= float(neighborCount);
        depthContinuity /= float(neighborCount);
        
        // Combine metrics with weights
        float qualityScore = localDensity * 0.4 + 
                           normalConsistency * 0.3 + 
                           depthContinuity * 0.3;
                           
        qualityScores[id] = qualityScore;
    } else {
        qualityScores[id] = 0.0;
    }
}

// Enhanced bilateral filter for noise reduction
kernel void adaptiveBilateralFilterKernel(
    device const Point* input [[buffer(0)]],
    device Point* output [[buffer(1)]],
    device const float* parameters [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    const float spatialSigma = parameters[0];
    const float rangeSigma = parameters[1];
    const float confidenceThreshold = parameters[2];
    Point centerPoint = input[id];
    
    float3 filteredPosition = 0;
    float3 filteredNormal = 0;
    float weightSum = 0;
    
    // Adapt filter strength based on point confidence
    float adaptiveSpatialSigma = spatialSigma;
    float adaptiveRangeSigma = rangeSigma;
    
    if (centerPoint.confidence < confidenceThreshold) {
        // Increase filter strength for low confidence points
        adaptiveSpatialSigma *= 1.5;
        adaptiveRangeSigma *= 1.5;
    }
    
    for (uint i = 0; i < id; i++) {
        Point neighbor = input[i];
        float3 diff = neighbor.position - centerPoint.position;
        float spatialDist = length(diff);
        
        if (spatialDist > adaptiveSpatialSigma * 3) continue; // 3-sigma cutoff
        
        float rangeDist = abs(neighbor.confidence - centerPoint.confidence);
        
        // Calculate bilateral weights
        float spatialWeight = exp(-spatialDist * spatialDist / (2 * adaptiveSpatialSigma * adaptiveSpatialSigma));
        float rangeWeight = exp(-rangeDist * rangeDist / (2 * adaptiveRangeSigma * adaptiveRangeSigma));
        float weight = spatialWeight * rangeWeight;
        
        filteredPosition += neighbor.position * weight;
        filteredNormal += neighbor.normal * weight;
        weightSum += weight;
    }
    
    if (weightSum > 0) {
        output[id].position = filteredPosition / weightSum;
        output[id].normal = normalize(filteredNormal / weightSum);
        // Preserve original confidence
        output[id].confidence = centerPoint.confidence;
    } else {
        output[id] = centerPoint;
    }
}