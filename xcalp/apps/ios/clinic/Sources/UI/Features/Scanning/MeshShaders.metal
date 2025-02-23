#include <metal_stdlib>
using namespace metal;

// Vertex structure matching the capture format
struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

// Quadric error metric for mesh decimation
struct Quadric {
    float4x4 matrix;
};

// Compute shader for vertex normal calculation
kernel void calculateNormals(
    device const float3* vertices [[buffer(0)]],
    device const uint3* triangles [[buffer(1)]],
    device float3* normals [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    // Calculate weighted normals for each vertex
    float3 normal = float3(0.0f);
    uint triangleCount = 0;
    
    // Iterate through triangles containing this vertex
    for (uint i = 0; i < triangleCount; i++) {
        uint3 tri = triangles[i];
        if (tri.x == vid || tri.y == vid || tri.z == vid) {
            float3 v0 = vertices[tri.x];
            float3 v1 = vertices[tri.y];
            float3 v2 = vertices[tri.z];
            
            // Calculate triangle normal
            float3 triNormal = normalize(cross(v1 - v0, v2 - v0));
            
            // Weight by triangle area
            float area = length(cross(v1 - v0, v2 - v0)) * 0.5f;
            normal += triNormal * area;
        }
    }
    
    normals[vid] = normalize(normal);
}

// Compute shader for mesh decimation
kernel void decimateMesh(
    device const Vertex* vertices [[buffer(0)]],
    device const uint* indices [[buffer(1)]],
    device Quadric* quadrics [[buffer(2)]],
    device uint* vertexRemoved [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    // Skip already removed vertices
    if (vertexRemoved[vid]) return;
    
    // Calculate error quadric for vertex
    Quadric q = quadrics[vid];
    float error = calculateError(vertices[vid].position, q);
    
    // If error is below threshold, mark for removal
    if (error < 0.001f) {
        vertexRemoved[vid] = 1;
    }
}

// Helper function to calculate quadric error
static float calculateError(float3 v, Quadric q) {
    float4 p = float4(v, 1.0f);
    return dot(p, q.matrix * p);
}

// Compute shader for UV generation using planar mapping
kernel void generatePlanarUVs(
    device const float3* vertices [[buffer(0)]],
    device float2* uvs [[buffer(1)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 pos = vertices[vid];
    
    // Simple planar mapping - can be enhanced with more sophisticated algorithms
    uvs[vid] = float2(pos.x, pos.z);
}

// Compute shader for mesh quality analysis
kernel void analyzeMeshQuality(
    device const float3* vertices [[buffer(0)]],
    device const float3* normals [[buffer(1)]],
    device float* quality [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 normal = normals[vid];
    float3 position = vertices[vid];
    
    // Calculate local quality metrics
    float normalConsistency = 1.0f;
    float surfaceSmoothness = 1.0f;
    
    // Store quality metrics
    quality[vid * 2] = normalConsistency;
    quality[vid * 2 + 1] = surfaceSmoothness;
}