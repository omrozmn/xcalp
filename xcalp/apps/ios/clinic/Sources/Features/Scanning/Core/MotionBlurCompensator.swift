import CoreImage
import CoreVideo
import CoreMotion
import simd

public class MotionBlurCompensator {
    private let motionManager = CMMotionManager()
    private let blurThreshold: Float = 0.3
    private let velocityThreshold: Float = 2.0
    private var lastFrameTime: TimeInterval = 0
    
    private var onBlurDetected: ((Float) -> Void)?
    
    public init(onBlurDetected: @escaping (Float) -> Void) {
        self.onBlurDetected = onBlurDetected
        setupMotionTracking()
    }
    
    private func setupMotionTracking() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates()
    }
    
    public func processFrame(_ pixelBuffer: CVPixelBuffer) -> Float {
        let currentTime = CACurrentMediaTime()
        let deltaTime = currentTime - lastFrameTime
        lastFrameTime = currentTime
        
        // Calculate motion blur based on device movement
        let motionBlur = calculateMotionBlur(deltaTime)
        
        // Calculate image-based blur
        let imageBlur = calculateImageBlur(pixelBuffer)
        
        // Combine both blur metrics
        let totalBlur = max(motionBlur, imageBlur)
        
        if totalBlur > blurThreshold {
            onBlurDetected?(totalBlur)
        }
        
        return totalBlur
    }
    
    private func calculateMotionBlur(_ deltaTime: TimeInterval) -> Float {
        guard let motion = motionManager.deviceMotion else { return 0 }
        
        let rotation = motion.rotationRate
        let acceleration = motion.userAcceleration
        
        // Calculate angular velocity magnitude
        let angularVelocity = sqrt(
            rotation.x * rotation.x +
            rotation.y * rotation.y +
            rotation.z * rotation.z
        )
        
        // Calculate linear velocity magnitude
        let linearVelocity = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        
        // Combine velocities and normalize
        let totalVelocity = Float(angularVelocity + linearVelocity)
        return min(totalVelocity / velocityThreshold, 1.0)
    }
    
    private func calculateImageBlur(_ pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        guard let blur = calculateLaplacianVariance(ciImage) else {
            return 0
        }
        
        // Normalize blur value
        return min(Float(blur) / 100.0, 1.0)
    }
    
    private func calculateLaplacianVariance(_ image: CIImage) -> Double? {
        let context = CIContext()
        
        // Convert to grayscale
        let grayscaleFilter = CIFilter(name: "CIPhotoEffectMono")
        grayscaleFilter?.setValue(image, forKey: kCIInputImageKey)
        
        guard let grayscaleImage = grayscaleFilter?.outputImage else { return nil }
        
        // Apply Laplacian kernel
        let laplacianKernel = CIKernel(source: """
            kernel vec4 laplacian(sampler image) {
                vec2 coord = destCoord();
                float kernel[9] = float[9](
                    -1.0, -1.0, -1.0,
                    -1.0,  8.0, -1.0,
                    -1.0, -1.0, -1.0
                );
                
                vec4 sum = vec4(0.0);
                int index = 0;
                
                for (int i = -1; i <= 1; i++) {
                    for (int j = -1; j <= 1; j++) {
                        vec2 offset = vec2(float(i), float(j));
                        sum += sample(image, coord + offset) * kernel[index];
                        index++;
                    }
                }
                
                return sum;
            }
        """)
        
        guard let laplacianFilter = CIFilter(name: "CustomKernel",
                                           withInputParameters: [
                                            kCIInputImageKey: grayscaleImage,
                                            "inputKernel": laplacianKernel as Any
                                           ]) else { return nil }
        
        guard let laplacianImage = laplacianFilter.outputImage else { return nil }
        
        // Calculate variance of Laplacian
        var variance: Double = 0
        var count: Int = 0
        
        let extent = laplacianImage.extent
        if let bitmap = context.createCGImage(laplacianImage, from: extent) {
            let width = bitmap.width
            let height = bitmap.height
            let bytesPerRow = bitmap.bytesPerRow
            let data = UnsafeMutablePointer<UInt8>.allocate(capacity: height * bytesPerRow)
            defer { data.deallocate() }
            
            let colorSpace = CGColorSpaceCreateDeviceGray()
            let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            
            guard let context = CGContext(data: data,
                                        width: width,
                                        height: height,
                                        bitsPerComponent: 8,
                                        bytesPerRow: bytesPerRow,
                                        space: colorSpace,
                                        bitmapInfo: bitmapInfo.rawValue) else {
                return nil
            }
            
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // Calculate variance
            var sum: Double = 0
            var squareSum: Double = 0
            
            for y in 0..<height {
                for x in 0..<width {
                    let pixel = Double(data[y * bytesPerRow + x])
                    sum += pixel
                    squareSum += pixel * pixel
                    count += 1
                }
            }
            
            let mean = sum / Double(count)
            variance = (squareSum / Double(count)) - (mean * mean)
        }
        
        return variance
    }
    
    public func compensateForBlur(_ points: [Point3D], blurAmount: Float) -> [Point3D] {
        // Apply compensation based on blur amount
        let compensation = 1.0 + blurAmount
        
        return points.map { point in
            Point3D(
                x: point.x * compensation,
                y: point.y * compensation,
                z: point.z * compensation
            )
        }
    }
    
    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}