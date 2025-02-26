#include <metal_stdlib>
using namespace metal;

struct QualityMetrics {
    float pointDensity;
    float featureQuality;
    float surfaceConsistency;
    float depthAccuracy;
};

kernel void analyzeDepthQualityKernel(
    texture2d<float, access::read> depthMap [[texture(0)]],
    texture2d<float, access::read> confidenceMap [[texture(1)]],
    device QualityMetrics* metrics [[buffer(0)]],
    uint2 pos [[thread_position_in_grid]]
) {
    if (pos.x >= depthMap.get_width() || pos.y >= depthMap.get_height()) {
        return;
    }
    
    // Read depth and confidence values
    float depth = depthMap.read(pos).r;
    float confidence = confidenceMap.read(pos).r;
    
    // Skip invalid depth values
    if (depth <= 0.0f) return;
    
    // Calculate local depth consistency
    float localConsistency = calculateLocalConsistency(
        depthMap,
        pos,
        depth
    );
    
    // Calculate surface normal using depth gradients
    float3 normal = calculateSurfaceNormal(
        depthMap,
        pos
    );
    
    // Update quality metrics atomically
    atomic_fetch_add_explicit(
        (device atomic_uint*)&metrics->surfaceConsistency,
        uint(localConsistency * 1000.0f),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_uint*)&metrics->depthAccuracy,
        uint(confidence * 1000.0f),
        memory_order_relaxed
    );
}

kernel void detectQualityIssuesKernel(
    texture2d<float, access::read> depthMap [[texture(0)]],
    texture2d<float, access::write> qualityMap [[texture(1)]],
    constant float& threshold [[buffer(0)]],
    uint2 pos [[thread_position_in_grid]]
) {
    if (pos.x >= depthMap.get_width() || pos.y >= depthMap.get_height()) {
        return;
    }
    
    float depth = depthMap.read(pos).r;
    float quality = 1.0f;
    
    if (depth > 0.0f) {
        // Check local neighborhood for depth consistency
        float localVariance = calculateLocalVariance(
            depthMap,
            pos,
            depth
        );
        
        // Check for depth discontinuities
        float discontinuity = detectDiscontinuities(
            depthMap,
            pos,
            depth
        );
        
        // Check surface orientation
        float3 normal = calculateSurfaceNormal(
            depthMap,
            pos
        );
        float orientation = dot(normal, float3(0, 0, 1));
        
        // Combine quality factors
        quality = min(
            1.0f,
            (1.0f - localVariance) *
            (1.0f - discontinuity) *
            orientation
        );
    }
    
    qualityMap.write(float4(quality), pos);
}

float calculateLocalConsistency(
    texture2d<float, access::read> depthMap,
    uint2 pos,
    float centerDepth
) {
    float totalVariance = 0.0f;
    float weightSum = 0.0f;
    
    // Sample 3x3 neighborhood
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 samplePos = int2(pos) + int2(dx, dy);
            
            // Skip out of bounds samples
            if (samplePos.x < 0 || samplePos.x >= depthMap.get_width() ||
                samplePos.y < 0 || samplePos.y >= depthMap.get_height()) {
                continue;
            }
            
            float sampleDepth = depthMap.read(uint2(samplePos)).r;
            if (sampleDepth <= 0.0f) continue;
            
            float diff = abs(sampleDepth - centerDepth);
            float weight = 1.0f / (1.0f + diff);
            
            totalVariance += diff * weight;
            weightSum += weight;
        }
    }
    
    return weightSum > 0.0f ? 1.0f - (totalVariance / weightSum) : 0.0f;
}

float3 calculateSurfaceNormal(
    texture2d<float, access::read> depthMap,
    uint2 pos
) {
    // Calculate depth gradients using Sobel operator
    float gx = 0.0f;
    float gy = 0.0f;
    
    // 3x3 Sobel kernels
    const float sobelX[3][3] = {
        {-1, 0, 1},
        {-2, 0, 2},
        {-1, 0, 1}
    };
    
    const float sobelY[3][3] = {
        {-1, -2, -1},
        {0, 0, 0},
        {1, 2, 1}
    };
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int2 samplePos = int2(pos) + int2(dx, dy);
            
            // Skip out of bounds samples
            if (samplePos.x < 0 || samplePos.x >= depthMap.get_width() ||
                samplePos.y < 0 || samplePos.y >= depthMap.get_height()) {
                continue;
            }
            
            float depth = depthMap.read(uint2(samplePos)).r;
            if (depth <= 0.0f) continue;
            
            gx += depth * sobelX[dy + 1][dx + 1];
            gy += depth * sobelY[dy + 1][dx + 1];
        }
    }
    
    // Construct normal from gradients
    float3 normal = normalize(float3(-gx, -gy, 1.0f));
    return normal;
}

float calculateLocalVariance(
    texture2d<float, access::read> depthMap,
    uint2 pos,
    float centerDepth
) {
    float sum = 0.0f;
    float sumSq = 0.0f;
    float count = 0.0f;
    
    // Sample 5x5 neighborhood
    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            int2 samplePos = int2(pos) + int2(dx, dy);
            
            if (samplePos.x < 0 || samplePos.x >= depthMap.get_width() ||
                samplePos.y < 0 || samplePos.y >= depthMap.get_height()) {
                continue;
            }
            
            float depth = depthMap.read(uint2(samplePos)).r;
            if (depth <= 0.0f) continue;
            
            sum += depth;
            sumSq += depth * depth;
            count += 1.0f;
        }
    }
    
    if (count < 1.0f) return 1.0f;
    
    float mean = sum / count;
    float variance = (sumSq / count) - (mean * mean);
    
    return sqrt(max(0.0f, variance)) / centerDepth;
}

float detectDiscontinuities(
    texture2d<float, access::read> depthMap,
    uint2 pos,
    float centerDepth
) {
    float maxDiff = 0.0f;
    
    // Check in 8 directions
    const int2 directions[8] = {
        {-1, -1}, {0, -1}, {1, -1},
        {-1,  0},          {1,  0},
        {-1,  1}, {0,  1}, {1,  1}
    };
    
    for (int i = 0; i < 8; i++) {
        int2 samplePos = int2(pos) + directions[i];
        
        if (samplePos.x < 0 || samplePos.x >= depthMap.get_width() ||
            samplePos.y < 0 || samplePos.y >= depthMap.get_height()) {
            continue;
        }
        
        float depth = depthMap.read(uint2(samplePos)).r;
        if (depth <= 0.0f) continue;
        
        float diff = abs(depth - centerDepth) / centerDepth;
        maxDiff = max(maxDiff, diff);
    }
    
    // Normalize discontinuity measure
    return min(1.0f, maxDiff / 0.1f); // 10% depth difference threshold
}