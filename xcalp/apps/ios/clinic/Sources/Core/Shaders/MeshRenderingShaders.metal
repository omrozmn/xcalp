#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Vertex shader inputs
struct VertexInput {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// Vertex shader outputs and fragment shader inputs
struct RasterizerData {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoord;
    float3 viewDirection;
};

// Uniform buffer data
struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
};

// Material properties
struct MaterialProperties {
    float4 ambientColor;
    float4 diffuseColor;
    float4 specularColor;
    float shininess;
    float opacity;
};

// Lighting properties
struct LightProperties {
    float3 position;
    float3 color;
    float intensity;
    float attenuation;
};

// Vertex shader
vertex RasterizerData vertexShader(
    const VertexInput vertexIn [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant MaterialProperties &material [[buffer(2)]]
) {
    RasterizerData out;
    
    // Transform position to world space
    float4 worldPosition = uniforms.modelMatrix * float4(vertexIn.position, 1.0);
    out.worldPosition = worldPosition.xyz;
    
    // Transform position to clip space
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    
    // Transform normal to world space
    out.worldNormal = normalize(uniforms.normalMatrix * vertexIn.normal);
    
    // Pass through texture coordinates
    out.texCoord = vertexIn.texCoord;
    
    // Calculate view direction
    float3 cameraPosition = float3(uniforms.viewMatrix[3].xyz);
    out.viewDirection = normalize(cameraPosition - worldPosition.xyz);
    
    return out;
}

// Fragment shader
fragment float4 fragmentShader(
    RasterizerData in [[stage_in]],
    constant MaterialProperties &material [[buffer(0)]],
    constant LightProperties &light [[buffer(1)]],
    texture2d<float> diffuseTexture [[texture(0)]],
    texture2d<float> normalTexture [[texture(1)]],
    texture2d<float> specularTexture [[texture(2)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample textures
    float4 diffuseColor = diffuseTexture.sample(textureSampler, in.texCoord);
    float3 normalMap = normalTexture.sample(textureSampler, in.texCoord).xyz * 2.0 - 1.0;
    float4 specularMap = specularTexture.sample(textureSampler, in.texCoord);
    
    // Calculate lighting vectors
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(light.position - in.worldPosition);
    float3 V = normalize(in.viewDirection);
    float3 H = normalize(L + V);
    
    // Apply normal mapping
    float3x3 TBN = getTBNMatrix(N, V, in.texCoord);
    N = normalize(TBN * normalMap);
    
    // Calculate lighting components
    float3 ambient = material.ambientColor.rgb * light.color;
    
    float diffuseFactor = max(dot(N, L), 0.0);
    float3 diffuse = diffuseColor.rgb * light.color * diffuseFactor;
    
    float specularFactor = pow(max(dot(N, H), 0.0), material.shininess);
    float3 specular = material.specularColor.rgb * light.color * specularFactor * specularMap.r;
    
    // Calculate attenuation
    float distance = length(light.position - in.worldPosition);
    float attenuation = 1.0 / (1.0 + light.attenuation * distance * distance);
    
    // Combine lighting components
    float3 finalColor = ambient + (diffuse + specular) * attenuation * light.intensity;
    
    // Apply rim lighting for edge highlighting
    float rimFactor = 1.0 - max(dot(N, V), 0.0);
    rimFactor = pow(rimFactor, 3.0);
    float3 rimColor = float3(0.5, 0.5, 1.0) * rimFactor;
    
    finalColor += rimColor;
    
    // Apply fog effect for depth perception
    float fogStart = 5.0;
    float fogEnd = 20.0;
    float fogFactor = (fogEnd - distance) / (fogEnd - fogStart);
    fogFactor = clamp(fogFactor, 0.0, 1.0);
    float3 fogColor = float3(0.8, 0.8, 0.8);
    
    finalColor = mix(fogColor, finalColor, fogFactor);
    
    return float4(finalColor, material.opacity);
}

// Utility functions
float3x3 getTBNMatrix(float3 N, float3 V, float2 texCoord) {
    // Calculate tangent and bitangent vectors
    float3 dp1 = dfdx(V);
    float3 dp2 = dfdy(V);
    float2 duv1 = dfdx(texCoord);
    float2 duv2 = dfdy(texCoord);
    
    float3x3 M = float3x3(dp1, dp2, N);
    float2x3 I = float2x3(duv1, duv2);
    
    float3 T = normalize((float3x3(M) * float3(I[0], 0.0)));
    float3 B = normalize((float3x3(M) * float3(I[1], 0.0)));
    
    // Ensure orthogonal and normalized basis
    T = normalize(T - N * dot(T, N));
    B = cross(N, T);
    
    return float3x3(T, B, N);
}

// Post-processing effects
float3 applyToneMapping(float3 color) {
    // Reinhard tone mapping
    return color / (color + 1.0);
}

float3 applyColorGrading(float3 color) {
    // Simple color grading
    float3 contrast = 1.1;
    float3 brightness = 0.1;
    float3 saturation = 1.2;
    
    // Adjust brightness and contrast
    color = (color - 0.5) * contrast + 0.5 + brightness;
    
    // Adjust saturation
    float luminance = dot(color, float3(0.299, 0.587, 0.114));
    color = mix(float3(luminance), color, saturation);
    
    return clamp(color, 0.0, 1.0);
}