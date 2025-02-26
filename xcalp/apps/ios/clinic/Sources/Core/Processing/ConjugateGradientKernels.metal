#include <metal_stdlib>
using namespace metal;

// Sparse matrix format structs
struct SparseMatrixData {
    device const uint* rows;      // Row indices
    device const uint* cols;      // Column indices
    device const float* values;   // Matrix values
    uint numNonZero;             // Number of non-zero elements
    uint size;                    // Matrix dimension
};

// Compute sparse matrix-vector product
kernel void sparseMatrixVectorProduct(
    constant SparseMatrixData& matrix [[buffer(0)]],
    device const float* vector [[buffer(1)]],
    device float* result [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= matrix.size) return;
    
    float sum = 0.0;
    for (uint i = 0; i < matrix.numNonZero; i++) {
        if (matrix.rows[i] == index) {
            sum += matrix.values[i] * vector[matrix.cols[i]];
        }
    }
    result[index] = sum;
}

// Update solution vectors for conjugate gradient
kernel void updateSolution(
    device float* x [[buffer(0)]],         // Solution vector
    device float* r [[buffer(1)]],         // Residual vector
    device const float* p [[buffer(2)]],   // Search direction
    device const float* Ap [[buffer(3)]],  // Matrix-vector product
    device float* scalars [[buffer(4)]],   // Alpha, rsnew, rsold, beta
    constant uint& size [[buffer(5)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= size) return;
    
    // Update solution and residual
    float alpha = scalars[0];
    x[index] += alpha * p[index];
    r[index] -= alpha * Ap[index];
}

// Compute dot products needed for conjugate gradient
kernel void computeDotProducts(
    device const float* r [[buffer(0)]],   // Residual vector
    device const float* p [[buffer(1)]],   // Search direction
    device const float* Ap [[buffer(2)]],  // Matrix-vector product
    device atomic_float* dotProducts [[buffer(3)]], // rsold, rsnew, pAp
    constant uint& size [[buffer(4)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= size) return;
    
    // Thread-local dot products
    float r_r = r[index] * r[index];
    float p_Ap = p[index] * Ap[index];
    
    // Atomic addition to accumulate results
    atomic_fetch_add_explicit(&dotProducts[0], r_r, memory_order_relaxed);
    atomic_fetch_add_explicit(&dotProducts[1], p_Ap, memory_order_relaxed);
}

// Update search direction
kernel void updateSearchDirection(
    device float* p [[buffer(0)]],         // Search direction
    device const float* r [[buffer(1)]],   // Residual vector
    constant float& beta [[buffer(2)]],    // Beta scalar
    constant uint& size [[buffer(3)]],
    uint index [[thread_position_in_grid]]
) {
    if (index >= size) return;
    p[index] = r[index] + beta * p[index];
}