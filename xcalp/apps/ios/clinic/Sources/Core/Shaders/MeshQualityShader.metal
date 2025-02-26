#include <metal_stdlib>
using namespace metal;

struct MeshQualityMetrics {
    float vertexDensity;
    float averageTriangleArea;
    float normalConsistency;
    float boundaryLength;
    float surfaceCurvature;
};

kernel void analyzeMeshQuality(
    const device packed_float3* vertices [[buffer(0)]],
    const device packed_float3* normals [[buffer(1)]],
    device MeshQualityMetrics* result [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    // Initialize accumulators
    thread float localDensity = 0.0;
    thread float localArea = 0.0;
    thread float localNormalConsistency = 0.0;
    thread float localBoundaryLength = 0.0;
    thread float localCurvature = 0.0;
    
    // Calculate vertex density
    const float searchRadius = 0.01; // 1cm radius
    for (uint i = 0; i < id; i++) {
        float3 diff = vertices[id] - vertices[i];
        float distSq = dot(diff, diff);
        if (distSq < searchRadius * searchRadius) {
            localDensity += 1.0;
        }
    }
    
    // Calculate surface properties for each vertex
    float3 position = vertices[id];
    float3 normal = normals[id];
    
    // Analyze local neighborhood
    const uint neighborhoodSize = 6;
    for (uint i = max(1u, id) - 1; i < min(id + 1, arrayLength(vertices)); i++) {
        if (i == id) continue;
        
        float3 neighborPos = vertices[i];
        float3 neighborNormal = normals[i];
        
        // Calculate triangle area
        float3 edge = neighborPos - position;
        float3 cross_product = cross(edge, normal);
        localArea += length(cross_product) * 0.5;
        
        // Normal consistency
        float normalAlignment = dot(normal, neighborNormal);
        localNormalConsistency += normalAlignment > 0.0 ? normalAlignment : 0.0;
        
        // Boundary detection
        float edgeLength = length(edge);
        localBoundaryLength += edgeLength;
        
        // Surface curvature
        float3 heightDiff = dot(edge, normal) * normal;
        localCurvature += length(heightDiff) / edgeLength;
    }
    
    // Normalize results
    localDensity /= float(id);
    localArea /= float(neighborhoodSize);
    localNormalConsistency /= float(neighborhoodSize);
    localBoundaryLength /= float(neighborhoodSize);
    localCurvature /= float(neighborhoodSize);
    
    // Atomic updates to global results
    atomic_fetch_add_explicit(
        (device atomic_uint*)&result->vertexDensity,
        as_type<uint>(localDensity),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_uint*)&result->averageTriangleArea,
        as_type<uint>(localArea),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_uint*)&result->normalConsistency,
        as_type<uint>(localNormalConsistency),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_uint*)&result->boundaryLength,
        as_type<uint>(localBoundaryLength),
        memory_order_relaxed
    );
    
    atomic_fetch_add_explicit(
        (device atomic_uint*)&result->surfaceCurvature,
        as_type<uint>(localCurvature),
        memory_order_relaxed
    );
}