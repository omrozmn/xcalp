#include <metal_stdlib>
#include "MetalTypes.h"
using namespace metal;

// Local mesh quality metrics
kernel void computeLocalQualityMetrics(
    device const MeshVertex* vertices [[buffer(0)]],
    device const uint* indices [[buffer(1)]],
    device float4* qualityMetrics [[buffer(2)]],
    device atomic_uint* histogram [[buffer(3)]],
    constant ProcessingParameters& params [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= indices[0]) return;  // indices[0] contains vertex count
    
    MeshVertex vertex = vertices[vid];
    float localDensity = 0;
    float normalConsistency = 0;
    float surfaceContinuity = 0;
    float featureStrength = 0;
    int validNeighbors = 0;
    
    // Analyze local neighborhood
    for (uint i = 1; i < indices[0]; i++) {
        if (i == vid) continue;
        
        MeshVertex neighbor = vertices[i];
        float3 diff = neighbor.position - vertex.position;
        float dist = length(diff);
        
        if (dist < params.spatialSigma * 3) {
            // Compute local density
            localDensity += 1.0 / (dist + 1e-5);
            
            // Compute normal consistency
            float normalAlignment = abs(dot(normalize(neighbor.normal), 
                                         normalize(vertex.normal)));
            normalConsistency += normalAlignment;
            
            // Compute surface continuity
            float heightDiff = abs(dot(diff, normalize(vertex.normal)));
            surfaceContinuity += 1.0 - min(heightDiff / params.rangeSigma, 1.0);
            
            // Compute feature strength using dihedral angle
            float angle = acos(normalAlignment);
            featureStrength = max(featureStrength, angle);
            
            validNeighbors++;
        }
    }
    
    // Normalize metrics
    if (validNeighbors > 0) {
        localDensity /= float(validNeighbors);
        normalConsistency /= float(validNeighbors);
        surfaceContinuity /= float(validNeighbors);
    }
    
    // Store results
    qualityMetrics[vid] = float4(
        localDensity,
        normalConsistency,
        surfaceContinuity,
        featureStrength
    );
    
    // Update histograms for global analysis
    uint densityBin = min(uint(localDensity * 32), 31u);
    uint consistencyBin = min(uint(normalConsistency * 32), 31u);
    atomic_fetch_add_explicit(&histogram[densityBin], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&histogram[32 + consistencyBin], 1, memory_order_relaxed);
}

// Global mesh quality assessment
kernel void computeGlobalQualityMetrics(
    device const float4* localMetrics [[buffer(0)]],
    device const uint* histogram [[buffer(1)]],
    device QualityMetrics* globalMetrics [[buffer(2)]],
    constant uint& vertexCount [[buffer(3)]],
    uint id [[thread_position_in_grid]]
) {
    if (id > 0) return; // Single thread computation
    
    // Analyze density distribution
    float weightedDensity = 0;
    float totalWeight = 0;
    
    for (uint i = 0; i < 32; i++) {
        float binCenter = (float(i) + 0.5) / 32.0;
        float weight = float(histogram[i]);
        weightedDensity += binCenter * weight;
        totalWeight += weight;
    }
    
    float averageDensity = weightedDensity / totalWeight;
    
    // Analyze normal consistency distribution
    float totalConsistency = 0;
    for (uint i = 0; i < 32; i++) {
        float binCenter = (float(i) + 0.5) / 32.0;
        totalConsistency += binCenter * float(histogram[32 + i]);
    }
    
    float averageConsistency = totalConsistency / totalWeight;
    
    // Compute global metrics
    globalMetrics->pointDensity = averageDensity * 1000.0; // Scale to points/m³
    globalMetrics->surfaceCompleteness = averageConsistency;
    
    // Compute noise level from surface continuity
    float totalNoise = 0;
    for (uint i = 0; i < vertexCount; i++) {
        totalNoise += 1.0 - localMetrics[i].z;
    }
    globalMetrics->noiseLevel = totalNoise / float(vertexCount);
    
    // Compute feature preservation from feature strengths
    float totalFeatures = 0;
    float significantFeatures = 0;
    for (uint i = 0; i < vertexCount; i++) {
        if (localMetrics[i].w > 0.5) { // Significant feature threshold
            significantFeatures += 1.0;
            totalFeatures += localMetrics[i].w;
        }
    }
    
    globalMetrics->featurePreservation = significantFeatures > 0 ? 
        totalFeatures / (significantFeatures * M_PI_F) : 1.0;
}