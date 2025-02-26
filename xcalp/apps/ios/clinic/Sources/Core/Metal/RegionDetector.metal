#include <metal_stdlib>
using namespace metal;

struct RegionParams {
    float hairlineThreshold;
    float crownThreshold;
    float templeThreshold;
    float blendingFactor;
    int smoothingRadius;
};

struct RegionMask {
    int type;
    float confidence;
};

kernel void detectRegions(
    device const float* heightMap [[ buffer(0) ]],
    device const float* curvatureMap [[ buffer(1) ]],
    device const float3* normals [[ buffer(2) ]],
    device RegionMask* regions [[ buffer(3) ]],
    constant RegionParams& params [[ buffer(4) ]],
    uint2 pos [[ thread_position_in_grid ]],
    uint2 size [[ threads_per_grid ]]
) {
    const uint x = pos.x;
    const uint y = pos.y;
    const uint resolution = size.x;
    
    if (x >= resolution || y >= resolution) {
        return;
    }
    
    const uint index = y * resolution + x;
    float height = heightMap[index];
    float curvature = curvatureMap[index];
    float3 normal = normals[index];
    
    // Initialize region mask
    RegionMask mask;
    mask.type = 0;
    mask.confidence = 0.0;
    
    // Hairline detection
    if (y < resolution/4) {
        float heightGradient = (height - heightMap[min(y + 1, resolution-1) * resolution + x]);
        if (heightGradient > params.hairlineThreshold) {
            mask.type = 1; // Hairline
            mask.confidence = min(1.0, heightGradient / params.hairlineThreshold);
        }
    }
    
    // Crown detection
    if (x > resolution/3 && x < 2*resolution/3 && 
        y > resolution/3 && y < 2*resolution/3) {
        if (curvature > params.crownThreshold) {
            float distanceFromCenter = length(float2(x - resolution/2, y - resolution/2));
            float crownConfidence = exp(-distanceFromCenter / (resolution/4));
            
            if (crownConfidence > mask.confidence) {
                mask.type = 2; // Crown
                mask.confidence = crownConfidence;
            }
        }
    }
    
    // Temple detection
    if ((x < resolution/3 || x > 2*resolution/3) && y < resolution/2) {
        float templeScore = curvature / params.templeThreshold;
        if (templeScore > mask.confidence) {
            mask.type = 3; // Temple
            mask.confidence = templeScore;
            // Distinguish left/right temple
            if (x < resolution/2) {
                mask.type = 31; // Left temple
            } else {
                mask.type = 32; // Right temple
            }
        }
    }
    
    // Mid-scalp detection (default region if no other strong detection)
    if (mask.confidence < 0.3) {
        float midScalpScore = 1.0 - (abs(curvature) / params.crownThreshold);
        mask.type = 4; // Mid-scalp
        mask.confidence = midScalpScore;
    }
    
    regions[index] = mask;
}

// Smooth region boundaries
kernel void smoothRegions(
    device const RegionMask* inputRegions [[ buffer(0) ]],
    device RegionMask* outputRegions [[ buffer(1) ]],
    constant RegionParams& params [[ buffer(2) ]],
    uint2 pos [[ thread_position_in_grid ]],
    uint2 size [[ threads_per_grid ]]
) {
    const uint x = pos.x;
    const uint y = pos.y;
    const uint resolution = size.x;
    
    if (x >= resolution || y >= resolution) {
        return;
    }
    
    const uint index = y * resolution + x;
    RegionMask currentMask = inputRegions[index];
    
    // Count neighboring region types within smoothing radius
    int regionCounts[5] = {0}; // 0-4 region types
    float totalConfidence = 0.0;
    
    for (int dy = -params.smoothingRadius; dy <= params.smoothingRadius; dy++) {
        for (int dx = -params.smoothingRadius; dx <= params.smoothingRadius; dx++) {
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            
            if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution) {
                RegionMask neighbor = inputRegions[ny * resolution + nx];
                int baseType = neighbor.type % 10; // Handle left/right temple variants
                if (baseType >= 0 && baseType < 5) {
                    float weight = exp(-(dx*dx + dy*dy) / 
                                    (2.0 * params.smoothingRadius * params.smoothingRadius));
                    regionCounts[baseType] += weight * neighbor.confidence;
                    totalConfidence += weight * neighbor.confidence;
                }
            }
        }
    }
    
    // Find dominant region type
    int maxCount = regionCounts[currentMask.type % 10];
    int dominantType = currentMask.type;
    
    for (int i = 0; i < 5; i++) {
        if (regionCounts[i] > maxCount) {
            maxCount = regionCounts[i];
            dominantType = i;
            // Preserve left/right temple distinction
            if (i == 3) {
                dominantType = (x < resolution/2) ? 31 : 32;
            }
        }
    }
    
    // Blend confidence with neighbors
    float blendedConfidence = mix(
        currentMask.confidence,
        maxCount / totalConfidence,
        params.blendingFactor
    );
    
    outputRegions[index] = RegionMask{
        dominantType,
        blendedConfidence
    };
}

// Generate boundary vertices for each region
kernel void generateBoundaries(
    device const RegionMask* regions [[ buffer(0) ]],
    device float3* boundaryVertices [[ buffer(1) ]],
    device atomic_int* vertexCount [[ buffer(2) ]],
    device const float* heightMap [[ buffer(3) ]],
    uint2 pos [[ thread_position_in_grid ]],
    uint2 size [[ threads_per_grid ]]
) {
    const uint x = pos.x;
    const uint y = pos.y;
    const uint resolution = size.x;
    
    if (x >= resolution-1 || y >= resolution-1) {
        return;
    }
    
    const uint index = y * resolution + x;
    RegionMask current = regions[index];
    
    // Check if this is a boundary pixel
    bool isBoundary = false;
    for (int dy = -1; dy <= 1 && !isBoundary; dy++) {
        for (int dx = -1; dx <= 1 && !isBoundary; dx++) {
            if (dx == 0 && dy == 0) continue;
            
            int nx = int(x) + dx;
            int ny = int(y) + dy;
            
            if (nx >= 0 && nx < resolution && ny >= 0 && ny < resolution) {
                RegionMask neighbor = regions[ny * resolution + nx];
                if (neighbor.type != current.type) {
                    isBoundary = true;
                }
            }
        }
    }
    
    // Add boundary vertex
    if (isBoundary) {
        int vIndex = atomic_fetch_add_explicit(vertexCount, 1, memory_order_relaxed);
        boundaryVertices[vIndex] = float3(
            float(x) / float(resolution),
            float(y) / float(resolution),
            heightMap[index]
        );
    }
}