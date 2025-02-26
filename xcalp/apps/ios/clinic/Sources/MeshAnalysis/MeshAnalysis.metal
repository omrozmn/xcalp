#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[position]];
    float3 normal;
};

kernel void analyzeMeshKernel(device const float3 *vertices [[buffer(0)]],
                            device const float3 *normals [[buffer(1)]],
                            device const uint *indices [[buffer(2)]],
                            device float *densityMap [[buffer(3)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= vertices.length()) {
        return;
    }
    
    // Calculate local density
    float3 currentVertex = vertices[id];
    float localDensity = 0.0;
    float searchRadius = 0.01; // 1cm radius
    
    for (uint i = 0; i < vertices.length(); i++) {
        if (i != id) {
            float3 difference = currentVertex - vertices[i];
            float distance = length(difference);
            if (distance < searchRadius) {
                localDensity += 1.0 - (distance / searchRadius);
            }
        }
    }
    
    // Calculate normal consistency
    float3 currentNormal = normals[id];
    float normalConsistency = 0.0;
    
    for (uint i = 0; i < indices.length(); i += 3) {
        if (indices[i] == id || indices[i + 1] == id || indices[i + 2] == id) {
            float3 n1 = normals[indices[i]];
            float3 n2 = normals[indices[i + 1]];
            float3 n3 = normals[indices[i + 2]];
            
            normalConsistency += dot(currentNormal, n1);
            normalConsistency += dot(currentNormal, n2);
            normalConsistency += dot(currentNormal, n3);
        }
    }
    
    // Store results in density map
    densityMap[id] = localDensity;
}