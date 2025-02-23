#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texCoord;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float3 cameraPosition;
    float densityThreshold;
};

// Vertex shader for region detection
vertex VertexOut region_vertex(const Vertex in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPosition;
    out.worldPosition = worldPosition.xyz;
    out.normal = (uniforms.modelMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = in.texCoord;
    return out;
}

// Fragment shader for region detection and analysis
fragment float4 region_fragment(VertexOut in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]],
                              texture2d<float> densityMap [[texture(0)]],
                              sampler densitySampler [[sampler(0)]]) {
    // Calculate view direction
    float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition);
    float3 normal = normalize(in.normal);
    
    // Sample density map
    float4 densityColor = densityMap.sample(densitySampler, in.texCoord);
    float density = densityColor.r;
    
    // Region classification based on density and surface orientation
    float regionScore = density * max(0.0, dot(normal, viewDir));
    float4 regionColor;
    
    if (regionScore > uniforms.densityThreshold) {
        // High density region
        regionColor = float4(1.0, 0.0, 0.0, 1.0);
    } else if (regionScore > uniforms.densityThreshold * 0.5) {
        // Medium density region
        regionColor = float4(0.0, 1.0, 0.0, 1.0);
    } else {
        // Low density region
        regionColor = float4(0.0, 0.0, 1.0, 1.0);
    }
    
    return regionColor;
}