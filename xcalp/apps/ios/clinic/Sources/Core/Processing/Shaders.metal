#include <metal_stdlib>
using namespace metal;

struct Point {
    float3 position;
    float3 normal;
    float confidence;
};

kernel void processPointsKernel(device const Point* input [[ buffer(0) ]],
                              device Point* output [[ buffer(1) ]],
                              uint id [[ thread_position_in_grid ]]) {
    // Copy input point
    Point point = input[id];
    
    // Apply processing based on confidence
    if (point.confidence < 0.5) {
        // Low confidence points get more aggressive processing
        point.position = round(point.position * 1000) / 1000; // Round to nearest mm
        point.normal = normalize(point.normal);
        point.confidence = max(point.confidence, 0.1f); // Enforce minimum confidence
    } else {
        // High confidence points get lighter processing
        point.normal = normalize(point.normal);
    }
    
    // Store processed point
    output[id] = point;
}

kernel void denoisePointsKernel(device const Point* input [[ buffer(0) ]],
                              device Point* output [[ buffer(1) ]],
                              device const float* parameters [[ buffer(2) ]],
                              uint id [[ thread_position_in_grid ]]) {
    const float radius = parameters[0];
    const float sigmaS = parameters[1];
    const float sigmaR = parameters[2];
    
    Point centerPoint = input[id];
    float3 filtered_position = 0;
    float3 filtered_normal = 0;
    float weight_sum = 0;
    
    // Bilateral filter implementation
    for (uint i = max(0, int(id) - 10); i < min(id + 11, id); i++) {
        Point neighbor = input[i];
        
        float spatial_dist = length(neighbor.position - centerPoint.position);
        if (spatial_dist > radius) continue;
        
        float range_dist = abs(neighbor.confidence - centerPoint.confidence);
        
        float weight = exp(-spatial_dist * spatial_dist / (2 * sigmaS * sigmaS)) *
                      exp(-range_dist * range_dist / (2 * sigmaR * sigmaR));
        
        filtered_position += neighbor.position * weight;
        filtered_normal += neighbor.normal * weight;
        weight_sum += weight;
    }
    
    if (weight_sum > 0) {
        output[id].position = filtered_position / weight_sum;
        output[id].normal = normalize(filtered_normal / weight_sum);
        output[id].confidence = centerPoint.confidence;
    } else {
        output[id] = centerPoint;
    }
}

kernel void calculatePointDensityKernel(device const Point* points [[ buffer(0) ]],
                                      device float* density [[ buffer(1) ]],
                                      device const float* parameters [[ buffer(2) ]],
                                      uint id [[ thread_position_in_grid ]]) {
    const float radius = parameters[0];
    Point centerPoint = points[id];
    int neighborCount = 0;
    
    // Count points within radius
    for (uint i = 0; i < id; i++) {
        float dist = length(points[i].position - centerPoint.position);
        if (dist <= radius) {
            neighborCount++;
        }
    }
    
    // Calculate density (points per cubic meter)
    float volume = 4.0f/3.0f * M_PI_F * radius * radius * radius;
    density[id] = float(neighborCount) / volume;
}