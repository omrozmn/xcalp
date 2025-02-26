#include <metal_stdlib>
using namespace metal;

struct AnatomicalFeature {
    float3 position;
    float3 normal;
    uint type;
    float confidence;
    uint uniqueID;
};

struct DetectionParams {
    float radius;
    float threshold;
    bool adaptiveThreshold;
    uint maxFeatures;
};

struct FeaturePreservationParams {
    float preservationStrength;
    float featureRadius;
    bool temporalSmoothing;
    float smoothingFactor;
};

// Detect anatomical features using local geometry analysis
kernel void detectAnatomicalFeaturesKernel(
    const device float3* vertices [[buffer(0)]],
    const device float3* normals [[buffer(1)]],
    device AnatomicalFeature* features [[buffer(2)]],
    device atomic_uint* featureCount [[buffer(3)]],
    constant DetectionParams& params [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertices.arrayLength()) return;
    
    float3 position = vertices[vid];
    float3 normal = normals[vid];
    
    // Calculate local geometric properties
    float curvature = calculateLocalCurvature(
        position,
        normal,
        vertices,
        normals,
        params.radius
    );
    
    float shapeIndex = calculateShapeIndex(
        position,
        normal,
        vertices,
        normals,
        params.radius
    );
    
    // Determine feature type and confidence
    uint featureType;
    float confidence;
    
    if (isLandmark(curvature, shapeIndex)) {
        featureType = 0; // landmark
        confidence = calculateLandmarkConfidence(curvature, shapeIndex);
    }
    else if (isContour(curvature, shapeIndex)) {
        featureType = 1; // contour
        confidence = calculateContourConfidence(curvature, shapeIndex);
    }
    else if (isJunction(curvature, shapeIndex)) {
        featureType = 2; // junction
        confidence = calculateJunctionConfidence(curvature, shapeIndex);
    }
    else {
        return; // Not a significant feature
    }
    
    // Only store high-confidence features
    float threshold = params.adaptiveThreshold ? 
        calculateAdaptiveThreshold(curvature) :
        params.threshold;
    
    if (confidence > threshold) {
        uint index = atomic_fetch_add_explicit(featureCount, 1, memory_order_relaxed);
        if (index < params.maxFeatures) {
            features[index].position = position;
            features[index].normal = normal;
            features[index].type = featureType;
            features[index].confidence = confidence;
            features[index].uniqueID = vid; // Use vertex ID as initial unique ID
        }
    }
}

// Track and preserve detected features during mesh processing
kernel void preserveFeaturesKernel(
    device float3* vertices [[buffer(0)]],
    device float3* normals [[buffer(1)]],
    const device AnatomicalFeature* features [[buffer(2)]],
    constant uint& featureCount [[buffer(3)]],
    constant FeaturePreservationParams& params [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertices.arrayLength()) return;
    
    float3 position = vertices[vid];
    float3 normal = normals[vid];
    float3 preservedPosition = position;
    float3 preservedNormal = normal;
    float totalWeight = 0.0;
    
    // Find nearby features and calculate their influence
    for (uint i = 0; i < featureCount; i++) {
        AnatomicalFeature feature = features[i];
        float3 diff = feature.position - position;
        float distance = length(diff);
        
        if (distance < params.featureRadius) {
            float weight = calculateFeatureWeight(
                distance,
                params.featureRadius,
                feature.confidence
            );
            
            preservedPosition += weight * feature.position;
            preservedNormal += weight * feature.normal;
            totalWeight += weight;
        }
    }
    
    // Apply feature preservation
    if (totalWeight > 0.0) {
        preservedPosition /= (1.0 + totalWeight);
        preservedNormal = normalize(preservedNormal);
        
        // Blend with original position based on preservation strength
        vertices[vid] = mix(
            position,
            preservedPosition,
            params.preservationStrength
        );
        
        normals[vid] = normalize(mix(
            normal,
            preservedNormal,
            params.preservationStrength
        ));
    }
}

// Helper functions for geometric analysis
float calculateLocalCurvature(
    float3 position,
    float3 normal,
    const device float3* vertices,
    const device float3* normals,
    float radius
) {
    float curvature = 0.0;
    float weightSum = 0.0;
    
    for (uint i = 0; i < vertices.arrayLength(); i++) {
        float3 diff = vertices[i] - position;
        float distance = length(diff);
        
        if (distance > 0.0001 && distance < radius) {
            float weight = 1.0 / distance;
            float normalDifference = 1.0 - dot(normal, normals[i]);
            
            curvature += weight * normalDifference;
            weightSum += weight;
        }
    }
    
    return weightSum > 0.0 ? curvature / weightSum : 0.0;
}

float calculateShapeIndex(
    float3 position,
    float3 normal,
    const device float3* vertices,
    const device float3* normals,
    float radius
) {
    // Calculate principal curvatures using local surface fitting
    float3x3 covariance = float3x3(0.0);
    float3 centroid = float3(0.0);
    float weightSum = 0.0;
    
    for (uint i = 0; i < vertices.arrayLength(); i++) {
        float3 diff = vertices[i] - position;
        float distance = length(diff);
        
        if (distance < radius) {
            float weight = 1.0 - (distance / radius);
            float3 weighted_diff = diff * weight;
            
            covariance += float3x3(
                weighted_diff.x * weighted_diff,
                weighted_diff.y * weighted_diff,
                weighted_diff.z * weighted_diff
            );
            
            centroid += weighted_diff;
            weightSum += weight;
        }
    }
    
    if (weightSum > 0.0) {
        centroid /= weightSum;
        covariance /= weightSum;
        covariance -= float3x3(
            centroid.x * centroid,
            centroid.y * centroid,
            centroid.z * centroid
        );
        
        // Calculate eigenvalues (principal curvatures)
        float k1, k2;
        calculatePrincipalCurvatures(covariance, k1, k2);
        
        // Calculate shape index
        float numerator = 2.0 * atan2(k1 + k2, k1 - k2);
        return numerator / M_PI_F;
    }
    
    return 0.0;
}

void calculatePrincipalCurvatures(float3x3 covariance, thread float& k1, thread float& k2) {
    // Simplified eigenvalue calculation for 2 largest eigenvalues
    float p1 = covariance[0][0] + covariance[1][1] + covariance[2][2];
    float p2 = covariance[0][0] * covariance[1][1] + 
               covariance[1][1] * covariance[2][2] + 
               covariance[2][2] * covariance[0][0] -
               covariance[0][1] * covariance[1][0] -
               covariance[1][2] * covariance[2][1] -
               covariance[2][0] * covariance[0][2];
    
    float p = p1 / 3.0;
    float q = p2 / 2.0;
    
    float phi = acos(q / pow(p, 1.5));
    
    k1 = 2.0 * sqrt(p) * cos(phi / 3.0);
    k2 = 2.0 * sqrt(p) * cos((phi + 2.0 * M_PI_F) / 3.0);
}

bool isLandmark(float curvature, float shapeIndex) {
    return curvature > 0.7 && abs(shapeIndex) > 0.8;
}

bool isContour(float curvature, float shapeIndex) {
    return curvature > 0.5 && abs(shapeIndex) < 0.3;
}

bool isJunction(float curvature, float shapeIndex) {
    return curvature > 0.6 && abs(shapeIndex) > 0.4 && abs(shapeIndex) < 0.6;
}

float calculateLandmarkConfidence(float curvature, float shapeIndex) {
    return curvature * abs(shapeIndex);
}

float calculateContourConfidence(float curvature, float shapeIndex) {
    return curvature * (1.0 - abs(shapeIndex));
}

float calculateJunctionConfidence(float curvature, float shapeIndex) {
    return curvature * (1.0 - abs(abs(shapeIndex) - 0.5));
}

float calculateFeatureWeight(float distance, float radius, float confidence) {
    float normalizedDistance = distance / radius;
    float spatialWeight = 1.0 - normalizedDistance * normalizedDistance;
    return spatialWeight * confidence;
}

float calculateAdaptiveThreshold(float curvature) {
    return mix(0.5, 0.9, smoothstep(0.3, 0.8, curvature));
}