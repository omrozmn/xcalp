#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[position]];
    float3 normal;
    float importance;
};

struct Triangle {
    uint3 indices;
    float3 normal;
    float quality;
};

struct DecimationParams {
    float qualityThreshold;
    float featureWeight;
    float maxEdgeLength;
    bool adaptiveDecimation;
};

struct QuadricMatrix {
    float4x4 data;
    
    QuadricMatrix() {
        data = float4x4(0.0f);
    }
};

// Calculate vertex quadric error matrices
kernel void calculateQuadricsKernel(
    const device Vertex* vertices [[buffer(0)]],
    const device Triangle* triangles [[buffer(1)]],
    device QuadricMatrix* quadrics [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    if (vid >= vertices.arrayLength()) return;
    
    QuadricMatrix q;
    float3 v = vertices[vid].position;
    
    // Accumulate quadrics from adjacent triangles
    for (uint i = 0; i < triangles.arrayLength(); i++) {
        Triangle tri = triangles[i];
        
        // Check if vertex belongs to this triangle
        if (tri.indices.x == vid || tri.indices.y == vid || tri.indices.z == vid) {
            float3 n = tri.normal;
            float d = -dot(n, v);
            
            // Construct plane equation: ax + by + cz + d = 0
            float4 plane = float4(n, d);
            
            // Add outer product to quadric
            q.data += float4x4(
                plane.x * plane,
                plane.y * plane,
                plane.z * plane,
                plane.w * plane
            );
        }
    }
    
    // Weight quadric by vertex importance
    q.data *= (1.0f + vertices[vid].importance * vertices[vid].importance);
    
    quadrics[vid] = q;
}

// Evaluate potential edge collapses
kernel void evaluateCollapseKernel(
    const device Vertex* vertices [[buffer(0)]],
    const device QuadricMatrix* quadrics [[buffer(1)]],
    device float* errors [[buffer(2)]],
    constant DecimationParams& params [[buffer(3)]],
    uint eid [[thread_position_in_grid]]
) {
    if (eid >= vertices.arrayLength()) return;
    
    float3 v1 = vertices[eid].position;
    float importance1 = vertices[eid].importance;
    QuadricMatrix q1 = quadrics[eid];
    float minError = INFINITY;
    
    // Evaluate collapse to each neighbor
    for (uint i = 0; i < vertices.arrayLength(); i++) {
        if (i == eid) continue;
        
        float3 v2 = vertices[i].position;
        float importance2 = vertices[i].importance;
        
        // Check edge length constraint
        float edgeLength = length(v2 - v1);
        if (edgeLength > params.maxEdgeLength) continue;
        
        // Calculate combined quadric
        QuadricMatrix q2 = quadrics[i];
        QuadricMatrix q = q1;
        q.data += q2.data;
        
        // Find optimal collapse position
        float3 optimal = solveQuadricPosition(q.data);
        
        // Calculate error at optimal position
        float error = evaluateQuadricError(optimal, q.data);
        
        // Weight error by feature importance
        float importanceWeight = max(importance1, importance2);
        error *= (1.0f + importanceWeight * params.featureWeight);
        
        minError = min(minError, error);
    }
    
    errors[eid] = minError;
}

// Perform edge collapses
kernel void collapseEdgesKernel(
    device Vertex* vertices [[buffer(0)]],
    device Triangle* triangles [[buffer(1)]],
    const device float* errors [[buffer(2)]],
    constant DecimationParams& params [[buffer(3)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= triangles.arrayLength()) return;
    
    Triangle tri = triangles[tid];
    uint3 indices = tri.indices;
    
    // Check if any edge should be collapsed
    float3 errors3 = float3(
        errors[indices.x],
        errors[indices.y],
        errors[indices.z]
    );
    
    if (all(errors3 > params.qualityThreshold)) return;
    
    // Find edge with minimum error
    uint minIndex = 0;
    float minError = errors3[0];
    
    for (uint i = 1; i < 3; i++) {
        if (errors3[i] < minError) {
            minError = errors3[i];
            minIndex = i;
        }
    }
    
    // Perform collapse if error is acceptable
    if (minError <= params.qualityThreshold) {
        uint v1 = indices[minIndex];
        uint v2 = indices[(minIndex + 1) % 3];
        
        // Calculate optimal position
        float3 optimal = calculateOptimalPosition(
            vertices[v1].position,
            vertices[v2].position,
            vertices[v1].importance,
            vertices[v2].importance
        );
        
        // Update vertex position and mark for removal
        vertices[v1].position = optimal;
        vertices[v2].position = float3(INFINITY);
        
        // Update triangle connectivity
        triangles[tid].indices[minIndex] = v1;
        triangles[tid].indices[(minIndex + 1) % 3] = v1;
    }
}

// Helper functions
float3 solveQuadricPosition(float4x4 quadric) {
    // Extract upper-left 3x3 matrix and solve
    float3x3 A = float3x3(
        quadric[0].xyz,
        quadric[1].xyz,
        quadric[2].xyz
    );
    
    float3 b = float3(
        -quadric[0].w,
        -quadric[1].w,
        -quadric[2].w
    );
    
    // Solve system using Cramer's rule
    float det = determinant(A);
    
    if (abs(det) < 1e-10) {
        return float3(0.0f);
    }
    
    return solve3x3(A, b);
}

float evaluateQuadricError(float3 position, float4x4 quadric) {
    float4 p = float4(position, 1.0f);
    return dot(p, quadric * p);
}

float3 calculateOptimalPosition(
    float3 v1,
    float3 v2,
    float importance1,
    float importance2
) {
    float w1 = importance1 / (importance1 + importance2);
    float w2 = 1.0f - w1;
    return v1 * w1 + v2 * w2;
}

float3x3 inverse3x3(float3x3 m) {
    float det = determinant(m);
    if (abs(det) < 1e-10) return float3x3(0.0f);
    
    float invDet = 1.0f / det;
    return float3x3(
        cross(m[1], m[2]) * invDet,
        cross(m[2], m[0]) * invDet,
        cross(m[0], m[1]) * invDet
    );
}

float3 solve3x3(float3x3 A, float3 b) {
    return inverse3x3(A) * b;
}