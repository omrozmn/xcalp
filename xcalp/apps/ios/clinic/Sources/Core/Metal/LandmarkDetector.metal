#include <metal_stdlib>
using namespace metal;

struct Landmark {
    float3 position;
    int type;
    float confidence;
};

struct LandmarkParams {
    float crownThreshold;
    float templeThreshold;
    float napeThreshold;
    float whirlThreshold;
    int windowSize;
    float minDistance;
};

// Local maximum detection for crown and whirl points
bool isLocalMaximum(
    device const float* heightMap,
    uint x,
    uint y,
    uint resolution,
    int windowSize
) {
    float center = heightMap[y * resolution + x];
    int halfWindow = windowSize / 2;
    
    for (int dy = -halfWindow; dy <= halfWindow; dy++) {
        for (int dx = -halfWindow; dx <= halfWindow; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            
            if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution) {
                if (heightMap[ny * resolution + nx] >= center) {
                    return false;
                }
            }
        }
    }
    
    return true;
}

// Detect flow patterns for whirl detection
float3 computeFlowPattern(
    device const float* curvatureMap,
    device const float3* normals,
    uint x,
    uint y,
    uint resolution
) {
    const int kernelSize = 3;
    float3 flow = float3(0.0);
    
    for (int dy = -kernelSize; dy <= kernelSize; dy++) {
        for (int dx = -kernelSize; dx <= kernelSize; dx++) {
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            
            if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution) {
                float3 normal = normals[ny * resolution + nx];
                float curvature = curvatureMap[ny * resolution + nx];
                float weight = exp(-(dx*dx + dy*dy) / (2.0 * kernelSize * kernelSize));
                
                flow += normal * curvature * weight;
            }
        }
    }
    
    return normalize(flow);
}

// Calculate confidence score for landmark detection
float calculateConfidence(
    device const float* heightMap,
    device const float* curvatureMap,
    uint x,
    uint y,
    uint resolution,
    int windowSize,
    float threshold
) {
    float height = heightMap[y * resolution + x];
    float curvature = curvatureMap[y * resolution + x];
    float maxDiff = 0.0;
    int halfWindow = windowSize / 2;
    
    for (int dy = -halfWindow; dy <= halfWindow; dy++) {
        for (int dx = -halfWindow; dx <= halfWindow; dx++) {
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            
            if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution) {
                float diff = abs(height - heightMap[ny * resolution + nx]);
                maxDiff = max(maxDiff, diff);
            }
        }
    }
    
    float heightScore = maxDiff / threshold;
    float curvatureScore = abs(curvature) / threshold;
    
    return min(1.0, (heightScore + curvatureScore) / 2.0);
}

kernel void detectLandmarks(
    device const float* heightMap [[ buffer(0) ]],
    device const float* curvatureMap [[ buffer(1) ]],
    device const float3* normals [[ buffer(2) ]],
    device Landmark* landmarks [[ buffer(3) ]],
    device atomic_int* landmarkCount [[ buffer(4) ]],
    constant LandmarkParams& params [[ buffer(5) ]],
    uint2 pos [[ thread_position_in_grid ]],
    uint2 size [[ threads_per_grid ]]
) {
    const uint x = pos.x;
    const uint y = pos.y;
    const uint resolution = size.x;
    
    if (x >= resolution-1 || y >= resolution-1) {
        return;
    }
    
    float height = heightMap[y * resolution + x];
    float curvature = curvatureMap[y * resolution + x];
    float3 normal = normals[y * resolution + x];
    
    // Check if point is a potential landmark
    bool isCrown = isLocalMaximum(heightMap, x, y, resolution, params.windowSize) &&
                  height > params.crownThreshold;
    
    bool isTemple = (x < resolution/4 || x > 3*resolution/4) &&
                   y < resolution/2 &&
                   curvature > params.templeThreshold;
    
    bool isNape = y > 3*resolution/4 &&
                  curvature < -params.napeThreshold;
    
    // Detect whirl points using flow pattern analysis
    float3 flow = computeFlowPattern(curvatureMap, normals, x, y, resolution);
    bool isWhirl = length(cross(flow, normal)) > params.whirlThreshold;
    
    // Calculate confidence for detected landmark
    float confidence = calculateConfidence(
        heightMap,
        curvatureMap,
        x, y,
        resolution,
        params.windowSize,
        params.crownThreshold
    );
    
    // Add landmark if confidence exceeds threshold and respects minimum distance
    if ((isCrown || isTemple || isNape || isWhirl) && confidence > 0.5) {
        int index = atomic_fetch_add_explicit(landmarkCount, 1, memory_order_relaxed);
        
        // Check minimum distance from existing landmarks
        bool tooClose = false;
        for (int i = 0; i < index; i++) {
            float3 diff = landmarks[i].position - float3(float(x), float(y), height);
            if (length(diff) < params.minDistance) {
                tooClose = true;
                break;
            }
        }
        
        if (!tooClose) {
            landmarks[index].position = float3(float(x), float(y), height);
            landmarks[index].confidence = confidence;
            
            if (isCrown) landmarks[index].type = 1;
            else if (isTemple) landmarks[index].type = 2;
            else if (isNape) landmarks[index].type = 3;
            else if (isWhirl) landmarks[index].type = 5;
        }
    }
}

// Post-processing kernel for landmark refinement
kernel void refineLandmarks(
    device Landmark* landmarks [[ buffer(0) ]],
    device const atomic_int* landmarkCount [[ buffer(1) ]],
    device const float* heightMap [[ buffer(2) ]],
    device const float* curvatureMap [[ buffer(3) ]],
    uint tid [[ thread_position_in_grid ]]
) {
    int count = atomic_load_explicit(landmarkCount, memory_order_relaxed);
    if (tid >= count) return;
    
    // Refine landmark position using weighted average of neighborhood
    Landmark& landmark = landmarks[tid];
    float3 refinedPosition = landmark.position;
    float totalWeight = 1.0;
    
    // ... refinement logic for landmark positions ...
    
    landmark.position = refinedPosition;
}