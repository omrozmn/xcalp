import Foundation

class ConjugateGradientSolver {
    /// Solves the linear system Ax = b using the Conjugate Gradient method.
    ///
    /// - Parameters:
    ///   - A: A function that performs the matrix-vector product Ax. It should accept a vector x and return the result Ax.
    ///   - b: The vector b in the linear system Ax = b.
    ///   - x0: An initial guess for the solution x.
    ///   - tolerance: The desired tolerance for the residual norm.
    ///   - maxIterations: The maximum number of iterations to perform.
    ///
    /// - Returns: An optional vector x that is the approximate solution to Ax = b, or nil if the method fails to converge.
    func solve(A: @escaping (([Double]) -> [Double]),
               b: [Double],
               x0: [Double],
               tolerance: Double,
               maxIterations: Int) -> [Double]? {

        var x = x0 // Current estimate of the solution
        var r = subtract(b, A(x)) // Residual vector
        var p = r // Conjugate direction vector

        var rsold = dotProduct(r, r) // Square of the residual norm

        for i in 0 ..< maxIterations {
            let Ap = A(p) // Matrix-vector product Ap
            let alpha = rsold / dotProduct(p, Ap) // Step size

            // Update the solution
            x = add(x, scale(alpha, p))

            // Update the residual
            r = subtract(r, scale(alpha, Ap))

            let rsnew = dotProduct(r, r) // New square of the residual norm

            // Check for convergence
            if sqrt(rsnew) < tolerance {
                print("Converged in \(i+1) iterations.")
                return x
            }

            // Update the conjugate direction
            let beta = rsnew / rsold
            p = add(r, scale(beta, p))

            rsold = rsnew // Update the old residual norm
        }

        print("Failed to converge after \(maxIterations) iterations.")
        return nil // Did not converge
    }

    /// Computes the dot product of two vectors.
    private func dotProduct(_ x: [Double], _ y: [Double]) -> Double {
        var sum: Double = 0.0
        for i in 0 ..< x.count {
            sum += x[i] * y[i]
        }
        return sum
    }

    /// Subtracts two vectors.
    private func subtract(_ x: [Double], _ y: [Double]) -> [Double] {
        var result: [Double] = []
        for i in 0 ..< x.count {
            result.append(x[i] - y[i])
        }
        return result
    }

    /// Adds two vectors.
    private func add(_ x: [Double], _ y: [Double]) -> [Double] {
        var result: [Double] = []
        for i in 0 ..< x.count {
            result.append(x[i] + y[i])
        }
        return result
    }

    /// Scales a vector by a scalar.
    private func scale(_ alpha: Double, _ x: [Double]) -> [Double] {
        var result: [Double] = []
        for i in 0 ..< x.count {
            result.append(alpha * x[i])
        }
        return result
    }
}
