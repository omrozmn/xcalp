import XCTest
import Combine
@testable import XcalpClinic

final class ScanningControllerTests: XCTestCase {
    var scanningController: ScanningController!
    var mockMeshProcessor: MeshProcessor!
    var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        mockMeshProcessor = MeshProcessor()
        scanningController = ScanningController(meshProcessor: mockMeshProcessor)
    }
    
    override func tearDown() {
        cancellables.removeAll()
        scanningController = nil
        mockMeshProcessor = nil
        super.tearDown()
    }
    
    func testFallbackMechanism() {
        // Given
        let expectation = XCTestExpectation(description: "Mode switch expectation")
        var receivedStates: [ScanningState] = []
        
        scanningController.scanningStatePublisher
            .sink { state in
                receivedStates.append(state)
                if case .modeSwitched = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        scanningController.startScanning()
        
        // Simulate poor lighting conditions
        let poorQuality = ScanQuality(
            lighting: 500, // Below minimum threshold
            motionScore: 0.3,
            featureScore: 0.9,
            pointDensity: 600
        )
        scanningController.handleQualityUpdate(poorQuality)
        
        // Then
        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(receivedStates.contains(where: { state in
            if case .modeSwitched(let mode) = state {
                return mode == .photogrammetry
            }
            return false
        }))
    }
    
    func testQualityMonitoring() {
        // Given
        let expectation = XCTestExpectation(description: "Quality monitoring expectation")
        
        // When
        scanningController.startScanning()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 3.0)
        // Verify that quality monitoring is active
        XCTAssertNotNil(scanningController.qualityMonitor)
    }
    
    func testMaxFallbackAttempts() {
        // Given
        let expectation = XCTestExpectation(description: "Max fallback attempts expectation")
        var receivedError: ScanningError?
        
        scanningController.scanningStatePublisher
            .sink { state in
                if case .failed(let error) = state {
                    receivedError = error
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        scanningController.startScanning()
        
        // Simulate multiple quality degradations
        for _ in 0...3 {
            let poorQuality = ScanQuality(
                lighting: 500,
                motionScore: 0.3,
                featureScore: 0.7,
                pointDensity: 400
            )
            scanningController.handleQualityUpdate(poorQuality)
        }
        
        // Then
        wait(for: [expectation], timeout: 10.0)
        XCTAssertNotNil(receivedError)
        if case .qualityThresholdNotMet? = receivedError {
            // Success
        } else {
            XCTFail("Expected qualityThresholdNotMet error")
        }
    }
    
    func testSessionInterruption() {
        // Given
        let expectation = XCTestExpectation(description: "Session interruption expectation")
        var receivedState: ScanningState?
        
        scanningController.scanningStatePublisher
            .sink { state in
                receivedState = state
                if case .interrupted = state {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When
        scanningController.startScanning()
        scanningController.sessionWasInterrupted(ARSession())
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedState, .interrupted)
    }
}