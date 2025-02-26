#ifndef MetalTypes_h
#define MetalTypes_h

#include <simd/simd.h>

typedef struct {
    vector_float3 position;
    vector_float3 normal;
    float confidence;
} MeshVertex;

typedef struct {
    vector_float3 min;
    vector_float3 max;
} BoundingBox;

typedef struct {
    float pointDensity;
    float surfaceCompleteness;
    float noiseLevel;
    float featurePreservation;
} QualityMetrics;

typedef struct {
    float spatialSigma;
    float rangeSigma;
    float confidenceThreshold;
    float featureWeight;
} ProcessingParameters;

#endif /* MetalTypes_h */