#include <metal_stdlib>
using namespace metal;

struct GridPoint {
    float value;
    float3 position;
    float3 gradient;
};

// Edge vertex interpolation helper
float3 interpolateVertex(float3 p1, float3 p2, float v1, float v2, float isoLevel) {
    if (abs(isoLevel - v1) < 0.00001) return p1;
    if (abs(isoLevel - v2) < 0.00001) return p2;
    if (abs(v1 - v2) < 0.00001) return p1;
    
    float mu = (isoLevel - v1) / (v2 - v1);
    return p1 + mu * (p2 - p1);
}

// Calculate gradient using central differences
float3 calculateGradient(device const float* field,
                        uint3 pos,
                        uint3 gridSize,
                        float cellSize) {
    float3 gradient;
    uint idx = pos.x + gridSize.x * (pos.y + gridSize.y * pos.z);
    
    // X gradient
    if (pos.x > 0 && pos.x < gridSize.x - 1) {
        gradient.x = (field[idx + 1] - field[idx - 1]) / (2 * cellSize);
    } else if (pos.x > 0) {
        gradient.x = (field[idx] - field[idx - 1]) / cellSize;
    } else {
        gradient.x = (field[idx + 1] - field[idx]) / cellSize;
    }
    
    // Y gradient
    if (pos.y > 0 && pos.y < gridSize.y - 1) {
        gradient.y = (field[idx + gridSize.x] - field[idx - gridSize.x]) / (2 * cellSize);
    } else if (pos.y > 0) {
        gradient.y = (field[idx] - field[idx - gridSize.x]) / cellSize;
    } else {
        gradient.y = (field[idx + gridSize.x] - field[idx]) / cellSize;
    }
    
    // Z gradient
    uint zStep = gridSize.x * gridSize.y;
    if (pos.z > 0 && pos.z < gridSize.z - 1) {
        gradient.z = (field[idx + zStep] - field[idx - zStep]) / (2 * cellSize);
    } else if (pos.z > 0) {
        gradient.z = (field[idx] - field[idx - zStep]) / cellSize;
    } else {
        gradient.z = (field[idx + zStep] - field[idx]) / cellSize;
    }
    
    return gradient;
}

kernel void marchingCubesKernel(device const float* field [[buffer(0)]],
                               device float3* vertices [[buffer(1)]],
                               device float3* normals [[buffer(2)]],
                               device uint* indices [[buffer(3)]],
                               device atomic_uint* counters [[buffer(4)]],
                               device const uchar* triTable [[buffer(5)]],
                               device const float& isoLevel [[buffer(6)]],
                               device const uint3& gridSize [[buffer(7)]],
                               uint3 pos [[thread_position_in_grid]]) {
    if (pos.x >= gridSize.x - 1 || pos.y >= gridSize.y - 1 || pos.z >= gridSize.z - 1) return;
    
    // Get the eight vertices of the current cube
    GridPoint cubeVerts[8];
    float cellSize = 1.0 / float(max(max(gridSize.x, gridSize.y), gridSize.z));
    
    for (int i = 0; i < 8; i++) {
        uint3 offset = uint3((i & 1) != 0, (i & 2) != 0, (i & 4) != 0);
        uint3 p = pos + offset;
        uint idx = p.x + gridSize.x * (p.y + gridSize.y * p.z);
        
        cubeVerts[i].value = field[idx];
        cubeVerts[i].position = float3(p) * cellSize;
        cubeVerts[i].gradient = calculateGradient(field, p, gridSize, cellSize);
    }
    
    // Calculate cube configuration index
    int cubeIndex = 0;
    for (int i = 0; i < 8; i++) {
        if (cubeVerts[i].value < isoLevel) {
            cubeIndex |= 1 << i;
        }
    }
    
    // Get number of vertices for this cube
    int numVerts = 0;
    while (triTable[cubeIndex * 16 + numVerts] != 255 && numVerts < 12) numVerts++;
    
    if (numVerts > 0) {
        // Add vertices and triangles
        uint baseVertex = atomic_fetch_add_explicit(counters, uint(numVerts), memory_order_relaxed);
        uint baseIndex = atomic_fetch_add_explicit(counters + 1, uint(numVerts), memory_order_relaxed);
        
        // Process each triangle
        for (int i = 0; i < numVerts; i += 3) {
            // Get edge indices for this triangle
            int edge1 = triTable[cubeIndex * 16 + i];
            int edge2 = triTable[cubeIndex * 16 + i + 1];
            int edge3 = triTable[cubeIndex * 16 + i + 2];
            
            // Get vertices and interpolate position
            for (int j = 0; j < 3; j++) {
                int edge = triTable[cubeIndex * 16 + i + j];
                int v1 = (edge & 1) + ((edge & 2) != 0 ? 2 : 0) + ((edge & 4) != 0 ? 4 : 0);
                int v2 = v1 + (edge & 8 ? 1 : edge & 16 ? 2 : 4);
                
                float3 pos = interpolateVertex(
                    cubeVerts[v1].position,
                    cubeVerts[v2].position,
                    cubeVerts[v1].value,
                    cubeVerts[v2].value,
                    isoLevel
                );
                
                float3 normal = normalize(mix(
                    cubeVerts[v1].gradient,
                    cubeVerts[v2].gradient,
                    (isoLevel - cubeVerts[v1].value) / (cubeVerts[v2].value - cubeVerts[v1].value)
                ));
                
                vertices[baseVertex + j] = pos;
                normals[baseVertex + j] = normal;
                indices[baseIndex + j] = baseVertex + j;
            }
        }
    }
}