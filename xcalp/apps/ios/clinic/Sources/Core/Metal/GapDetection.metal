#include <metal_stdlib>
using namespace metal;

kernel void detectGapsKernel(
    texture2d<float, access::read> depthMap [[texture(0)]],
    texture2d<float, access::write> gapMap [[texture(1)]],
    constant float& threshold [[buffer(0)]],
    uint2 pos [[thread_position_in_grid]]
) {
    if (pos.x >= depthMap.get_width() || pos.y >= depthMap.get_height()) {
        return;
    }
    
    float depth = depthMap.read(pos).r;
    bool isGap = false;
    
    if (depth <= 0.0) {
        isGap = true;
    } else {
        // Check neighborhood for depth discontinuity
        const int radius = 2;
        float minDepth = depth;
        float maxDepth = depth;
        
        for (int dy = -radius; dy <= radius; dy++) {
            for (int dx = -radius; dx <= radius; dx++) {
                int2 nPos = int2(pos) + int2(dx, dy);
                if (nPos.x < 0 || nPos.x >= depthMap.get_width() ||
                    nPos.y < 0 || nPos.y >= depthMap.get_height()) {
                    continue;
                }
                
                float nDepth = depthMap.read(uint2(nPos)).r;
                if (nDepth > 0.0) {
                    minDepth = min(minDepth, nDepth);
                    maxDepth = max(maxDepth, nDepth);
                }
            }
        }
        
        isGap = (maxDepth - minDepth) > threshold;
    }
    
    gapMap.write(float4(isGap ? 1.0 : 0.0), pos);
}