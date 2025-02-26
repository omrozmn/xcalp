#include <metal_stdlib>
using namespace metal;

struct TextureVertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// UV unwrapping kernel
kernel void unwrapMeshUVs(
    const device float3* vertices [[buffer(0)]],
    const device float3* normals [[buffer(1)]],
    device float2* uvCoordinates [[buffer(2)]],
    constant uint& resolution [[buffer(3)]],
    uint vid [[thread_position_in_grid]]
) {
    float3 normal = normalize(normals[vid]);
    float3 position = vertices[vid];
    
    // Project 3D position onto 2D using spherical mapping
    float theta = atan2(normal.z, normal.x);
    float phi = acos(normal.y);
    
    // Convert spherical coordinates to UV coordinates
    float u = (theta + M_PI_F) / (2.0 * M_PI_F);
    float v = phi / M_PI_F;
    
    // Apply resolution scaling and ensure UVs are in [0,1] range
    u = fract(u * float(resolution)) / float(resolution);
    v = fract(v * float(resolution)) / float(resolution);
    
    uvCoordinates[vid] = float2(u, v);
}

// Texture blending kernel
kernel void blendTextures(
    texture2d<float, access::read> sourceTextures [[texture(0)]],
    texture2d<float, access::write> destinationTexture [[texture(1)]],
    constant float* weights [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= destinationTexture.get_width() || gid.y >= destinationTexture.get_height()) {
        return;
    }
    
    float4 blendedColor = 0;
    float totalWeight = 0;
    
    // Blend multiple texture samples
    for (uint i = 0; i < sourceTextures.get_array_size(); i++) {
        float weight = weights[i];
        float4 sample = sourceTextures.read(gid, i);
        
        blendedColor += sample * weight;
        totalWeight += weight;
    }
    
    // Normalize by total weight
    if (totalWeight > 0) {
        blendedColor /= totalWeight;
    }
    
    destinationTexture.write(blendedColor, gid);
}

// Normal map generation kernel
kernel void calculateLighting(
    const device float3* vertices [[buffer(0)]],
    const device float3* normals [[buffer(1)]],
    const device uint* indices [[buffer(2)]],
    texture2d<float, access::write> normalMap [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= normalMap.get_width() || gid.y >= normalMap.get_height()) {
        return;
    }
    
    // Calculate tangent space basis
    float3 tangent = 0;
    float3 bitangent = 0;
    
    // Sample neighboring vertices to compute tangent space
    for (uint i = 0; i < indices[gid.y * normalMap.get_width() + gid.x]; i += 3) {
        uint i1 = indices[i];
        uint i2 = indices[i + 1];
        uint i3 = indices[i + 2];
        
        float3 v1 = vertices[i1];
        float3 v2 = vertices[i2];
        float3 v3 = vertices[i3];
        
        float3 edge1 = v2 - v1;
        float3 edge2 = v3 - v1;
        
        tangent += normalize(edge1);
        bitangent += normalize(edge2);
    }
    
    tangent = normalize(tangent);
    bitangent = normalize(bitangent);
    
    // Calculate normal in tangent space
    float3 normal = normalize(cross(tangent, bitangent));
    
    // Convert normal from [-1,1] to [0,1] range for texture storage
    float4 normalColor = float4(normal * 0.5 + 0.5, 1.0);
    normalMap.write(normalColor, gid);
}

// Ambient occlusion calculation kernel
kernel void calculateAmbientOcclusion(
    const device float3* vertices [[buffer(0)]],
    const device float3* normals [[buffer(1)]],
    const device float2* uvCoords [[buffer(2)]],
    texture2d<float, access::write> aoMap [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= aoMap.get_width() || gid.y >= aoMap.get_height()) {
        return;
    }
    
    const int numSamples = 32;
    const float radius = 0.5;
    float occlusion = 0.0;
    
    // Get position and normal for current texel
    uint vertexIndex = gid.y * aoMap.get_width() + gid.x;
    float3 position = vertices[vertexIndex];
    float3 normal = normalize(normals[vertexIndex]);
    
    // Generate sample points in hemisphere
    for (int i = 0; i < numSamples; i++) {
        // Generate random sample in hemisphere using hammersley sequence
        float2 xi = hammersley(i, numSamples);
        float3 sample = hemispherePoint(xi, normal);
        
        // Scale sample by radius
        float3 samplePos = position + sample * radius;
        
        // Check for occlusion by other geometry
        float occluded = checkOcclusion(samplePos, position, vertices, normals, numSamples);
        occlusion += occluded;
    }
    
    // Normalize occlusion value
    occlusion = 1.0 - (occlusion / float(numSamples));
    aoMap.write(float4(occlusion, 0, 0, 1), gid);
}

// Utility functions
float2 hammersley(uint i, uint n) {
    float2 p;
    p.x = float(i) / float(n);
    p.y = radicalInverse(i);
    return p;
}

float radicalInverse(uint i) {
    i = (i << 16u) | (i >> 16u);
    i = ((i & 0x55555555u) << 1u) | ((i & 0xAAAAAAAAu) >> 1u);
    i = ((i & 0x33333333u) << 2u) | ((i & 0xCCCCCCCCu) >> 2u);
    i = ((i & 0x0F0F0F0Fu) << 4u) | ((i & 0xF0F0F0F0u) >> 4u);
    i = ((i & 0x00FF00FFu) << 8u) | ((i & 0xFF00FF00u) >> 8u);
    return float(i) * 2.3283064365386963e-10;
}

float3 hemispherePoint(float2 xi, float3 normal) {
    float phi = 2.0 * M_PI_F * xi.x;
    float cosTheta = sqrt(1.0 - xi.y);
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    
    float3 h;
    h.x = cos(phi) * sinTheta;
    h.y = sin(phi) * sinTheta;
    h.z = cosTheta;
    
    // Transform hemisphere to align with normal
    float3 up = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 tangent = normalize(cross(up, normal));
    float3 bitangent = cross(normal, tangent);
    
    return tangent * h.x + bitangent * h.y + normal * h.z;
}

float checkOcclusion(
    float3 samplePos,
    float3 position,
    const device float3* vertices,
    const device float3* normals,
    int numSamples
) {
    float occluded = 0.0;
    float3 rayDir = normalize(samplePos - position);
    
    // Simple ray-surface intersection test
    for (int i = 0; i < numSamples; i++) {
        float3 vertex = vertices[i];
        float3 normal = normals[i];
        
        float d = dot(rayDir, normal);
        if (d < 0) {
            float3 v = vertex - position;
            float t = dot(v, normal) / d;
            if (t > 0 && t < length(samplePos - position)) {
                occluded = 1.0;
                break;
            }
        }
    }
    
    return occluded;
}