#include <metal_stdlib>
using namespace metal;

struct Point {
    float3 position;
    float3 normal;
    float confidence;
};

struct ProcessingParameters {
    float spatialSigma;
    float rangeSigma;
    float confidenceThreshold;
    float featureWeight;
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

// Quality metrics computation
kernel void calculateQualityMetricsKernel(
    device const Point* points [[buffer(0)]],
    device float* qualityScores [[buffer(1)]],
    device const ProcessingParameters& params [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    Point centerPoint = points[id];
    float localDensity = 0;
    float normalConsistency = 0;
    float depthContinuity = 0;
    int validNeighbors = 0;
    
    // Calculate local quality metrics
    for (uint i = 0; i < id; i++) {
        Point neighbor = points[i];
        float dist = length(neighbor.position - centerPoint.position);
        
        if (dist < params.spatialSigma * 3) {
            // Local density
            localDensity += 1.0 / (dist + 1e-5);
            
            // Normal consistency
            float normalAlignment = dot(normalize(neighbor.normal), normalize(centerPoint.normal));
            normalConsistency += abs(normalAlignment);
            
            // Depth continuity
            float depthDiff = abs(length(neighbor.position) - length(centerPoint.position));
            depthContinuity += 1.0 - min(depthDiff / params.rangeSigma, 1.0);
            
            validNeighbors++;
        }
    }
    
    if (validNeighbors > 0) {
        // Normalize and combine metrics
        localDensity /= float(validNeighbors);
        normalConsistency /= float(validNeighbors);
        depthContinuity /= float(validNeighbors);
        
        float qualityScore = localDensity * 0.4 +
                            normalConsistency * 0.3 +
                            depthContinuity * 0.3;
                            
        qualityScores[id] = qualityScore * centerPoint.confidence;
    } else {
        qualityScores[id] = 0.0;
    }
}

// Enhanced bilateral filter for noise reduction
kernel void adaptiveBilateralFilterKernel(
    device const Point* input [[buffer(0)]],
    device Point* output [[buffer(1)]],
    device const ProcessingParameters& params [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    Point centerPoint = input[id];
    float3 filteredPosition = 0;
    float3 filteredNormal = 0;
    float weightSum = 0;
    
    // Adapt filter strength based on local features
    float adaptiveSpatialSigma = params.spatialSigma;
    float adaptiveRangeSigma = params.rangeSigma;
    
    if (centerPoint.confidence < params.confidenceThreshold) {
        // Increase filtering for low confidence points
        adaptiveSpatialSigma *= 1.5;
        adaptiveRangeSigma *= 1.5;
    }
    
    // Feature-preserving filtering
    for (uint i = 0; i < id; i++) {
        Point neighbor = input[i];
        float3 diff = neighbor.position - centerPoint.position;
        float spatialDist = length(diff);
        
        if (spatialDist > adaptiveSpatialSigma * 3) continue;
        
        float featureDist = abs(dot(normalize(neighbor.normal), normalize(centerPoint.normal)));
        float confidenceDist = abs(neighbor.confidence - centerPoint.confidence);
        
        // Calculate bilateral weights
        float spatialWeight = exp(-spatialDist * spatialDist / (2 * adaptiveSpatialSigma * adaptiveSpatialSigma));
        float rangeWeight = exp(-confidenceDist * confidenceDist / (2 * adaptiveRangeSigma * adaptiveRangeSigma));
        float featureWeight = pow(featureDist, params.featureWeight);
        
        float weight = spatialWeight * rangeWeight * featureWeight;
        
        filteredPosition += neighbor.position * weight;
        filteredNormal += neighbor.normal * weight;
        weightSum += weight;
    }
    
    // Normalize filtered results
    if (weightSum > 0) {
        output[id].position = filteredPosition / weightSum;
        output[id].normal = normalize(filteredNormal / weightSum);
        output[id].confidence = centerPoint.confidence;
    } else {
        output[id] = centerPoint;
    }
}

// Feature detection kernel
kernel void detectFeaturesKernel(
    device const Point* points [[buffer(0)]],
    device float* featureScores [[buffer(1)]],
    device const ProcessingParameters& params [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    Point centerPoint = points[id];
    float featureScore = 0;
    int validNeighbors = 0;
    
    // Calculate local geometric features
    for (uint i = 0; i < id; i++) {
        Point neighbor = points[i];
        float3 diff = neighbor.position - centerPoint.position;
        float dist = length(diff);
        
        if (dist < params.spatialSigma * 3) {
            // Calculate local surface variation
            float3 normalDiff = neighbor.normal - centerPoint.normal;
            float normalVariation = length(normalDiff) / (dist + 1e-5);
            
            // Calculate local curvature
            float3 projectedDiff = diff - dot(diff, centerPoint.normal) * centerPoint.normal;
            float curvature = length(projectedDiff) / (dist * dist + 1e-5);
            
            featureScore += normalVariation * 0.6 + curvature * 0.4;
            validNeighbors++;
        }
    }
    
    if (validNeighbors > 0) {
        featureScores[id] = (featureScore / float(validNeighbors)) * centerPoint.confidence;
    } else {
        featureScores[id] = 0.0;
    }
}