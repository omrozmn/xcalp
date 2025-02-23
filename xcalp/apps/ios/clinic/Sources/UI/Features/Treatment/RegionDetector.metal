#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position;
};

kernel void createDepthMapKernel(
    const device Vertex *vertices [[buffer(0)]],
    const device uint& vertexCount [[buffer(1)]],
    texture2d<float, access::write> depthMap [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    // Check if thread is within texture bounds
    if (gid.x >= depthMap.get_width() || gid.y >= depthMap.get_height()) {
        return;
    }
    
    // Convert grid coordinates to UV space
    float2 uv = float2(gid) / float2(depthMap.get_width(), depthMap.get_height());
    
    // Initialize depth value
    float minDepth = INFINITY;
    
    // Project vertices to UV space and find minimum depth
    for (uint i = 0; i < vertexCount; i++) {
        float3 pos = vertices[i].position;
        
        // Simple orthographic projection
        float2 projectedUV = float2(pos.x, pos.y) * 0.5 + 0.5;
        float distance = length(uv - projectedUV);
        
        if (distance < 0.01) {  // Threshold for depth contribution
            minDepth = min(minDepth, pos.z);
        }
    }
    
    // Write depth value
    float4 result = minDepth != INFINITY ? float4(minDepth) : float4(0.0);
    depthMap.write(result, gid);
}