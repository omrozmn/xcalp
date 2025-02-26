#include <metal_stdlib>
using namespace metal;

kernel void computeCurvature(
    device const float3* vertices [[ buffer(0) ]],
    device float* curvature [[ buffer(1) ]],
    uint2 gid [[ thread_position_in_grid ]],
    uint2 gridSize [[ threads_per_grid ]]
) {
    const int resolution = gridSize.x;
    const int index = gid.y * resolution + gid.x;
    
    if (gid.x >= resolution || gid.y >= resolution) {
        return;
    }
    
    // Convert grid position to normalized coordinates
    float2 uv = float2(gid) / float2(resolution - 1);
    
    // Find nearest vertices and compute local curvature
    float totalCurvature = 0.0;
    int sampleCount = 0;
    
    const int searchRadius = 3;
    for (int dy = -searchRadius; dy <= searchRadius; dy++) {
        for (int dx = -searchRadius; dx <= searchRadius; dx++) {
            int nx = gid.x + dx;
            int ny = gid.y + dy;
            
            if (nx < 0 || nx >= resolution || ny < 0 || ny >= resolution) {
                continue;
            }
            
            int nIndex = ny * resolution + nx;
            if (nIndex >= 0 && nIndex < resolution * resolution) {
                float3 p0 = vertices[index];
                float3 p1 = vertices[nIndex];
                
                // Compute discrete mean curvature using Laplace-Beltrami operator
                float3 diff = p1 - p0;
                totalCurvature += length(diff);
                sampleCount++;
            }
        }
    }
    
    // Average and normalize curvature
    if (sampleCount > 0) {
        curvature[index] = totalCurvature / float(sampleCount);
    } else {
        curvature[index] = 0.0;
    }
}