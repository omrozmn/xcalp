#include <metal_stdlib>
using namespace metal;

// Custom vertex descriptor for efficient mesh processing
struct MeshVertexData {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// Output data for vertex shader
struct VertexOutput {
    float4 position [[position]];
    float3 normal;
    float2 texCoord;
};

// Mesh decimation kernel using quadric error metrics
kernel void decimateMeshKernel(
    device float3 *vertices [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    device uint *indices [[buffer(2)]],
    device atomic_uint &vertexCount [[buffer(3)]],
    constant float &errorThreshold [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    // Skip if vertex already removed
    if (vid >= atomic_load_explicit(&vertexCount, memory_order_relaxed)) {
        return;
    }
    
    // Calculate quadric error matrix
    float4x4 Q = float4x4(0.0);
    float3 v = vertices[vid];
    float3 n = normals[vid];
    
    // Build error quadric
    float4 p = float4(n, -dot(n, v));
    Q += float4x4(
        p.x * p.x, p.x * p.y, p.x * p.z, p.x * p.w,
        p.y * p.x, p.y * p.y, p.y * p.z, p.y * p.w,
        p.z * p.x, p.z * p.y, p.z * p.z, p.z * p.w,
        p.w * p.x, p.w * p.y, p.w * p.z, p.w * p.w
    );
    
    // Check error against threshold
    float error = dot(float4(v, 1.0), Q * float4(v, 1.0));
    if (error < errorThreshold) {
        // Mark vertex for removal by decrementing count
        atomic_fetch_sub_explicit(&vertexCount, 1, memory_order_relaxed);
    }
}

// Surface optimization kernel
kernel void optimizeSurfaceKernel(
    device float3 *vertices [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    constant uint &vertexCount [[buffer(2)]],
    constant float &smoothingFactor [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertexCount) return;
    
    // Laplacian smoothing
    float3 centroid = float3(0.0);
    float3 avgNormal = float3(0.0);
    uint neighborCount = 0;
    
    // Gather neighboring vertices within radius
    for (uint i = 0; i < vertexCount; i++) {
        if (i == vid) continue;
        
        float3 diff = vertices[i] - vertices[vid];
        float dist = length(diff);
        
        if (dist < 0.1) { // Neighbor threshold
            centroid += vertices[i];
            avgNormal += normals[i];
            neighborCount++;
        }
    }
    
    if (neighborCount > 0) {
        centroid /= float(neighborCount);
        avgNormal = normalize(avgNormal / float(neighborCount));
        
        // Update position with smoothing factor
        vertices[vid] = mix(vertices[vid], centroid, smoothingFactor);
        normals[vid] = normalize(mix(normals[vid], avgNormal, smoothingFactor));
    }
}

// Normal calculation kernel
kernel void calculateNormalsKernel(
    device float3 *vertices [[buffer(0)]],
    device float3 *normals [[buffer(1)]],
    device uint3 *triangles [[buffer(2)]],
    constant uint &triangleCount [[buffer(3)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= triangleCount) return;
    
    uint3 tri = triangles[tid];
    float3 v0 = vertices[tri.x];
    float3 v1 = vertices[tri.y];
    float3 v2 = vertices[tri.z];
    
    // Calculate face normal
    float3 normal = normalize(cross(v1 - v0, v2 - v0));
    
    // Contribute to vertex normals
    atomic_store_explicit((device atomic_float*)&normals[tri.x], normal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.x + 1], normal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.x + 2], normal.z, memory_order_relaxed);
    
    atomic_store_explicit((device atomic_float*)&normals[tri.y], normal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.y + 1], normal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.y + 2], normal.z, memory_order_relaxed);
    
    atomic_store_explicit((device atomic_float*)&normals[tri.z], normal.x, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.z + 1], normal.y, memory_order_relaxed);
    atomic_store_explicit((device atomic_float*)&normals[tri.z + 2], normal.z, memory_order_relaxed);
}