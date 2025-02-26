#include <metal_stdlib>
using namespace metal;

struct Point {
    float3 position;
    float meanDistance;
    bool isOutlier;
};

// Calculate distances between points
kernel void calculateDistances(device Point* points [[buffer(0)]],
                             device float* distances [[buffer(1)]],
                             uint index [[thread_position_in_grid]],
                             uint grid_size [[threads_per_grid]]) {
    if (index >= grid_size) return;
    
    float3 currentPoint = points[index].position;
    float sumDistances = 0.0;
    int k = 30; // k nearest neighbors
    int validNeighbors = 0;
    
    // Calculate distances to k nearest neighbors
    for (uint i = 0; i < grid_size && validNeighbors < k; i++) {
        if (i == index) continue;
        
        float3 otherPoint = points[i].position;
        float dist = length(currentPoint - otherPoint);
        
        sumDistances += dist;
        validNeighbors++;
    }
    
    // Store mean distance
    if (validNeighbors > 0) {
        points[index].meanDistance = sumDistances / float(validNeighbors);
    }
}

// Identify outliers based on statistical analysis
kernel void identifyOutliers(device Point* points [[buffer(0)]],
                           constant float& stdDevThreshold [[buffer(1)]],
                           uint index [[thread_position_in_grid]],
                           uint grid_size [[threads_per_grid]]) {
    if (index >= grid_size) return;
    
    // Calculate mean and standard deviation of distances
    float meanOfMeans = 0.0;
    float stdDev = 0.0;
    
    // First pass: calculate mean
    for (uint i = 0; i < grid_size; i++) {
        meanOfMeans += points[i].meanDistance;
    }
    meanOfMeans /= float(grid_size);
    
    // Second pass: calculate standard deviation
    for (uint i = 0; i < grid_size; i++) {
        float diff = points[i].meanDistance - meanOfMeans;
        stdDev += diff * diff;
    }
    stdDev = sqrt(stdDev / float(grid_size));
    
    // Mark point as outlier if it's outside the threshold
    float threshold = meanOfMeans + stdDevThreshold * stdDev;
    points[index].isOutlier = points[index].meanDistance > threshold;
}