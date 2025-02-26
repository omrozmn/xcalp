#include <metal_stdlib>
using namespace metal;

struct MetricsParams {
    float areaThreshold;
    float normalThreshold;
    float triangleQualityThreshold;
    int samplingRadius;
};

struct QualityMetrics {
    float vertexDensity;
    float normalConsistency;
    float triangleQuality;
    float coverage;
};

// Compute triangle quality metrics
float computeTriangleQuality(float3 v1, float3 v2, float3 v3) {
    float3 edge1 = v2 - v1;
    float3 edge2 = v3 - v1;
    float3 edge3 = v3 - v2;
    
    float a = length(edge1);
    float b = length(edge2);
    float c = length(edge3);
    
    // Compute area using Heron's formula
    float s = (a + b + c) / 2.0;
    float area = sqrt(s * (s - a) * (s - b) * (s - c));
    
    // Compute minimum angle using law of cosines
    float minAngle = M_PI;
    float angleA = acos(dot(edge1, edge2) / (a * b));
    float angleB = acos(-dot(edge1, edge3) / (a * c));
    float angleC = M_PI - angleA - angleB;
    
    minAngle = min(minAngle, angleA);
    minAngle = min(minAngle, angleB);
    minAngle = min(minAngle, angleC);
    
    // Quality metric based on minimum angle and area
    return (minAngle / (M_PI / 3.0)) * (area / (a * b * c));
}

// Check vertex coverage uniformity
float computeCoverage(
    device const float3* vertices,
    uint index,
    uint vertexCount,
    float radius,
    uint resolution
) {
    float3 center = vertices[index];
    int neighbors = 0;
    float maxGap = 0.0;
    
    for (uint i = 0; i < vertexCount; i++) {
        if (i == index) continue;
        
        float3 diff = vertices[i] - center;
        float dist = length(diff);
        
        if (dist < radius) {
            neighbors++;
            // Track maximum gap between neighboring vertices
            for (uint j = 0; j < vertexCount; j++) {
                if (j == i || j == index) continue;
                float3 otherDiff = vertices[j] - center;
                if (length(otherDiff) < radius) {
                    float gap = length(normalize(diff) - normalize(otherDiff));
                    maxGap = max(maxGap, gap);
                }
            }
        }
    }
    
    float coverage = float(neighbors) / (M_PI * radius * radius * resolution);
    float uniformity = 1.0 - min(1.0, maxGap / (2.0 * M_PI));
    
    return coverage * uniformity;
}

kernel void computeSurfaceMetrics(
    device const float3* vertices [[ buffer(0) ]],
    device const float3* normals [[ buffer(1) ]],
    device const uint3* indices [[ buffer(2) ]],
    device QualityMetrics* metrics [[ buffer(3) ]],
    constant MetricsParams& params [[ buffer(4) ]],
    uint tid [[ thread_position_in_grid ]],
    uint threads [[ threads_per_grid ]]
) {
    if (tid >= threads) return;
    
    // Initialize local metrics
    float localTriangleQuality = 0.0;
    float localNormalConsistency = 0.0;
    float localCoverage = 0.0;
    int triangleCount = 0;
    
    // Process triangles
    uint triangleIndex = tid * 3;
    if (triangleIndex + 2 < threads * 3) {
        uint3 triangle = indices[triangleIndex / 3];
        float3 v1 = vertices[triangle.x];
        float3 v2 = vertices[triangle.y];
        float3 v3 = vertices[triangle.z];
        
        // Compute triangle quality
        float quality = computeTriangleQuality(v1, v2, v3);
        if (quality > params.triangleQualityThreshold) {
            localTriangleQuality += quality;
            triangleCount++;
            
            // Compute normal consistency
            float3 n1 = normals[triangle.x];
            float3 n2 = normals[triangle.y];
            float3 n3 = normals[triangle.z];
            
            float consistency = (dot(n1, n2) + dot(n2, n3) + dot(n3, n1)) / 3.0;
            localNormalConsistency += consistency;
        }
    }
    
    // Compute vertex coverage
    localCoverage = computeCoverage(
        vertices,
        tid,
        threads,
        params.samplingRadius,
        uint(sqrt(float(threads)))
    );
    
    // Atomic updates to global metrics
    if (triangleCount > 0) {
        atomic_fetch_add_explicit(
            (device atomic_int*)&metrics->triangleQuality,
            as_type<int>(localTriangleQuality / float(triangleCount)),
            memory_order_relaxed
        );
        
        atomic_fetch_add_explicit(
            (device atomic_int*)&metrics->normalConsistency,
            as_type<int>(localNormalConsistency / float(triangleCount)),
            memory_order_relaxed
        );
    }
    
    atomic_fetch_add_explicit(
        (device atomic_int*)&metrics->coverage,
        as_type<int>(localCoverage),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_int*)&metrics->vertexDensity,
        as_type<int>(float(threads) / (4.0 * M_PI)),
        memory_order_relaxed
    );
}

kernel void computeCurvatureMetrics(
    device const float3* vertices [[ buffer(0) ]],
    device const float3* normals [[ buffer(1) ]],
    device const uint* indices [[ buffer(2) ]],
    device float* curvatures [[ buffer(3) ]],
    device float* featureMetrics [[ buffer(4) ]],
    constant uint& vertexCount [[ buffer(5) ]],
    uint vid [[ thread_position_in_grid ]]
) {
    if (vid >= vertexCount) return;
    
    float3 vertex = vertices[vid];
    float3 normal = normals[vid];
    float maxCurvature = 0.0;
    float featureStrength = 0.0;
    
    // Analyze local neighborhood for curvature
    for (uint i = 0; i < vertexCount; i++) {
        if (i == vid) continue;
        float3 diff = vertices[i] - vertex;
        float dist = length(diff);
        
        if (dist < NEIGHBORHOOD_RADIUS) {
            float3 neighborNormal = normals[i];
            float angle = acos(dot(normal, neighborNormal));
            maxCurvature = max(maxCurvature, angle / dist);
            
            // Feature detection based on normal variation
            if (angle > FEATURE_ANGLE_THRESHOLD) {
                featureStrength += 1.0;
            }
        }
    }
    
    curvatures[vid] = maxCurvature;
    featureMetrics[vid] = featureStrength;
}