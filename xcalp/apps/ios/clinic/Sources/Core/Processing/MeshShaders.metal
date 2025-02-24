#include <metal_stdlib>
using namespace metal;

// Data structures
struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct FeatureMetrics {
    float curvature;
    float saliency;
    float confidence;
};

// Helper functions
float3 calculateCurvature(const device Vertex* vertices, uint vid, uint vertexCount) {
    float3 curvature = 0;
    int neighborCount = 0;
    
    // Use a local neighborhood for curvature calculation
    for (uint i = 0; i < vertexCount; i++) {
        if (i == vid) continue;
        
        float3 diff = vertices[i].position - vertices[vid].position;
        float dist = length(diff);
        
        if (dist < 0.01) { // Threshold for neighborhood
            curvature += vertices[i].normal - vertices[vid].normal;
            neighborCount++;
        }
    }
    
    return neighborCount > 0 ? curvature / float(neighborCount) : 0;
}

float calculateFeatureIntensity(float3 curvature) {
    return saturate(length(curvature) * 5.0); // Scale factor for feature detection
}

// Kernel functions
kernel void calculateNormals(
    device const float3* vertices [[buffer(0)]],
    device float3* normals [[buffer(1)]],
    device FeatureMetrics* features [[buffer(2)]],
    uint vid [[thread_position_in_grid]]
) {
    constexpr int kNeighborCount = 20;
    float3 position = vertices[vid];
    float3 normal = float3(0.0);
    float curvature = 0.0;
    
    // Covariance analysis for normal estimation
    float3x3 covariance = float3x3(0.0);
    int neighborCount = 0;
    
    for (int i = max(0, int(vid) - kNeighborCount/2); 
         i < min(int(vid) + kNeighborCount/2, int(vid)); 
         i++) {
        float3 neighbor = vertices[i];
        float3 diff = neighbor - position;
        covariance += float3x3(
            diff.x * diff.x, diff.x * diff.y, diff.x * diff.z,
            diff.y * diff.x, diff.y * diff.y, diff.y * diff.z,
            diff.z * diff.x, diff.z * diff.y, diff.z * diff.z
        );
        neighborCount++;
    }
    
    if (neighborCount > 0) {
        covariance /= float(neighborCount);
        
        // Find smallest eigenvalue direction (normal)
        float3 eigenvalues;
        float3x3 eigenvectors;
        eigenDecomposition(covariance, eigenvalues, eigenvectors);
        normal = eigenvectors[2]; // Smallest eigenvalue direction
        
        // Calculate curvature from eigenvalues
        curvature = eigenvalues[0] / (eigenvalues[0] + eigenvalues[1] + eigenvalues[2]);
    }
    
    // Calculate feature saliency
    float saliency = calculateSaliency(position, normal, vertices, vid, kNeighborCount);
    
    normals[vid] = normalize(normal);
    features[vid] = FeatureMetrics{
        curvature,
        saliency,
        min(1.0f, curvature + saliency)
    };
}

kernel void smoothMesh(
    device float3* vertices [[buffer(0)]],
    device const float3* normals [[buffer(1)]],
    device const FeatureMetrics* features [[buffer(2)]],
    constant float& smoothingFactor [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 position = vertices[vid];
    float3 normal = normals[vid];
    float featureWeight = 1.0 - features[vid].confidence;
    
    // Compute adaptive Laplacian
    float3 centroid = float3(0.0);
    int neighborCount = 0;
    
    for (int i = max(0, int(vid) - 20); i < min(int(vid) + 20, int(vid)); i++) {
        if (i != vid) {
            centroid += vertices[i];
            neighborCount++;
        }
    }
    
    if (neighborCount > 0) {
        centroid /= float(neighborCount);
        float3 offset = centroid - position;
        
        // Adjust smoothing based on feature weight
        float adaptiveFactor = smoothingFactor * featureWeight;
        vertices[vid] = position + offset * adaptiveFactor;
    }
}

kernel void decimateMesh(
    device float3* vertices [[buffer(0)]],
    device float3* normals [[buffer(1)]],
    device const FeatureMetrics* features [[buffer(2)]],
    device atomic_uint* vertexFlags [[buffer(3)]],
    constant float& targetError [[buffer(4)]],
    uint vid [[thread_position_in_grid]]
) {
    if (features[vid].confidence > 0.7) {
        // Preserve high-confidence features
        atomic_store_explicit(vertexFlags + vid, 1, memory_order_relaxed);
        return;
    }
    
    float error = calculateDecimationError(
        vertices[vid],
        normals[vid],
        vertices,
        normals,
        vid
    );
    
    if (error < targetError) {
        atomic_store_explicit(vertexFlags + vid, 0, memory_order_relaxed);
    } else {
        atomic_store_explicit(vertexFlags + vid, 1, memory_order_relaxed);
    }
}

// Utility functions
float calculateSaliency(
    float3 position,
    float3 normal,
    device const float3* vertices,
    uint index,
    int neighborCount
) {
    float saliency = 0.0;
    int count = 0;
    
    for (int i = max(0, int(index) - neighborCount/2);
         i < min(int(index) + neighborCount/2, int(index));
         i++) {
        if (i != index) {
            float3 diff = normalize(vertices[i] - position);
            saliency += abs(dot(diff, normal));
            count++;
        }
    }
    
    return count > 0 ? (1.0 - saliency / float(count)) : 0.0;
}

float calculateDecimationError(
    float3 vertex,
    float3 normal,
    device const float3* vertices,
    device const float3* normals,
    uint index
) {
    float error = 0.0;
    int count = 0;
    
    for (int i = max(0, int(index) - 10); i < min(int(index) + 10, int(index)); i++) {
        if (i != index) {
            float3 diff = vertices[i] - vertex;
            float dist = length(diff);
            float normalDev = 1.0 - abs(dot(normal, normals[i]));
            error += dist * (1.0 + normalDev);
            count++;
        }
    }
    
    return count > 0 ? error / float(count) : 0.0;
}

// Matrix operations
void eigenDecomposition(
    float3x3 matrix,
    thread float3& eigenvalues,
    thread float3x3& eigenvectors
) {
    // Simple power iteration for dominant eigenpair
    float3 v = normalize(float3(1.0, 1.0, 1.0));
    for (int i = 0; i < 8; ++i) {
        v = normalize(matrix * v);
    }
    
    float3 v1 = v;
    float lambda1 = dot(matrix * v1, v1);
    
    // Deflate matrix and find second eigenpair
    float3x3 deflated = matrix - lambda1 * (v1 * v1);
    v = normalize(float3(1.0, 0.0, 0.0));
    for (int i = 0; i < 8; ++i) {
        v = normalize(deflated * v);
    }
    
    float3 v2 = v;
    float lambda2 = dot(matrix * v2, v2);
    
    // Last eigenvector is cross product
    float3 v3 = cross(v1, v2);
    float lambda3 = dot(matrix * v3, v3);
    
    eigenvalues = float3(lambda1, lambda2, lambda3);
    eigenvectors = float3x3(v1, v2, v3);
}