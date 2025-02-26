#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

struct CoverageData {
    bool sectors[8];
    float3 centerPoint;
    float radius;
};

struct HeatmapData {
    float values[1024]; // 32x32
    uint2 dimensions;
    float minValue;
    float maxValue;
};

struct MarkerData {
    float3 position;
    uint type;
    float importance;
};

struct UniformBuffer {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float4x4 modelMatrix;
    float progress;
    float time;
};

// Color utilities
float3 heatmapColor(float value) {
    float4 colors[5] = {
        float4(0.0, 0.0, 1.0, 1.0),   // Blue (cold)
        float4(0.0, 1.0, 1.0, 1.0),   // Cyan
        float4(0.0, 1.0, 0.0, 1.0),   // Green
        float4(1.0, 1.0, 0.0, 1.0),   // Yellow
        float4(1.0, 0.0, 0.0, 1.0)    // Red (hot)
    };
    
    value = saturate(value);
    float idx = value * 4;
    int i = int(floor(idx));
    float f = fract(idx);
    
    if (i < 4) {
        return mix(colors[i].rgb, colors[i + 1].rgb, f);
    } else {
        return colors[4].rgb;
    }
}

vertex VertexOut visualizationVertexShader(
    const VertexIn vertex [[stage_in]],
    constant UniformBuffer& uniforms [[buffer(0)]],
    constant CoverageData& coverage [[buffer(1)]],
    constant MarkerData* markers [[buffer(2)]],
    uint instanceId [[instance_id]]
) {
    VertexOut out;
    
    float4x4 mvp = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix;
    
    switch (vertex.position.z) {
        case 0: // Coverage map
            float angle = float(instanceId) * M_PI_F * 0.25;
            float3 position = coverage.centerPoint + coverage.radius * float3(
                cos(angle) * vertex.position.x,
                sin(angle) * vertex.position.x,
                vertex.position.y
            );
            out.position = mvp * float4(position, 1.0);
            out.color = coverage.sectors[instanceId] ?
                float4(0.0, 1.0, 0.0, 0.5) :  // Covered
                float4(1.0, 0.0, 0.0, 0.3);   // Not covered
            break;
            
        case 1: // Markers
            float3 markerPos = markers[instanceId].position;
            out.position = mvp * float4(markerPos, 1.0);
            
            // Marker type colors
            switch (markers[instanceId].type) {
                case 0: // Missing coverage
                    out.color = float4(1.0, 0.0, 0.0, markers[instanceId].importance);
                    break;
                case 1: // Poor quality
                    out.color = float4(1.0, 0.5, 0.0, markers[instanceId].importance);
                    break;
                case 2: // Suggested path
                    float pulse = 0.5 + 0.5 * sin(uniforms.time * 2.0);
                    out.color = float4(0.0, 1.0, 0.0, markers[instanceId].importance * pulse);
                    break;
                default: // Warning
                    out.color = float4(1.0, 1.0, 0.0, markers[instanceId].importance);
            }
            break;
            
        default: // Progress indicator
            float progressAngle = uniforms.progress * 2.0 * M_PI_F;
            float3 position = float3(
                cos(progressAngle) * vertex.position.x,
                sin(progressAngle) * vertex.position.x,
                vertex.position.y
            );
            out.position = mvp * float4(position, 1.0);
            out.color = float4(0.0, 1.0, 0.0, 1.0);
    }
    
    out.texCoord = vertex.texCoord;
    return out;
}

fragment float4 visualizationFragmentShader(
    VertexOut in [[stage_in]],
    constant HeatmapData& heatmap [[buffer(0)]]
) {
    // Sample heatmap
    uint2 texelCoord = uint2(
        in.texCoord.x * float(heatmap.dimensions.x),
        in.texCoord.y * float(heatmap.dimensions.y)
    );
    
    uint index = texelCoord.y * heatmap.dimensions.x + texelCoord.x;
    float value = (heatmap.values[index] - heatmap.minValue) /
                  (heatmap.maxValue - heatmap.minValue);
    
    // Blend with vertex color
    float3 heatColor = heatmapColor(value);
    return float4(mix(heatColor, in.color.rgb, in.color.a), 1.0);
}

// Point sprite shader for markers
vertex VertexOut markerVertexShader(
    uint vertexID [[vertex_id]],
    constant MarkerData* markers [[buffer(0)]],
    constant UniformBuffer& uniforms [[buffer(1)]]
) {
    float2 positions[4] = {
        float2(-1, -1),
        float2( 1, -1),
        float2(-1,  1),
        float2( 1,  1)
    };
    
    VertexOut out;
    float2 position = positions[vertexID];
    
    float size = markers[vertexID].importance * 20.0; // Scale with importance
    float3 worldPos = markers[vertexID].position;
    
    float4x4 mvp = uniforms.projectionMatrix * uniforms.viewMatrix * uniforms.modelMatrix;
    out.position = mvp * float4(worldPos, 1.0);
    out.position.xy += position * size * out.position.w;
    
    out.texCoord = (position + 1.0) * 0.5;
    
    switch (markers[vertexID].type) {
        case 0: // Missing coverage
            out.color = float4(1.0, 0.0, 0.0, 1.0);
            break;
        case 1: // Poor quality
            out.color = float4(1.0, 0.5, 0.0, 1.0);
            break;
        case 2: // Suggested path
            float pulse = 0.5 + 0.5 * sin(uniforms.time * 2.0);
            out.color = float4(0.0, 1.0, 0.0, pulse);
            break;
        default: // Warning
            out.color = float4(1.0, 1.0, 0.0, 1.0);
    }
    
    return out;
}

fragment float4 markerFragmentShader(
    VertexOut in [[stage_in]]
) {
    // Create circular point sprite
    float2 center = float2(0.5, 0.5);
    float dist = distance(in.texCoord, center);
    float alpha = 1.0 - smoothstep(0.45, 0.5, dist);
    
    // Add glow effect
    float glow = exp(-dist * 5.0) * 0.5;
    float3 color = mix(in.color.rgb, float3(1.0), glow);
    
    return float4(color, alpha * in.color.a);
}