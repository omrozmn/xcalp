import XCTest
import ComposableArchitecture
@testable import XcalpClinic

final class ScanningFeatureTests: XCTestCase {
    func testDeviceCapabilityCheck() async {
        let store = TestStore(
            initialState: ScanningFeature.State(),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.checkDeviceCapabilities = { true }
        }
        
        await store.send(.onAppear)
        await store.receive(.checkDeviceCapabilities)
        await store.receive(.deviceCapabilitiesResult(.success(true)))
    }
    
    func testDeviceNotCapable() async {
        let store = TestStore(
            initialState: ScanningFeature.State(),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.checkDeviceCapabilities = { false }
        }
        
        await store.send(.onAppear)
        await store.receive(.checkDeviceCapabilities)
        await store.receive(.deviceCapabilitiesResult(.success(false)))
        await store.receive(.errorOccurred(.deviceNotCapable)) {
            $0.error = .deviceNotCapable
        }
    }
    
    func testStartScanning() async {
        let store = TestStore(
            initialState: ScanningFeature.State(),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.monitorScanQuality = {
                AsyncStream { continuation in
                    continuation.yield(.good)
                    continuation.finish()
                }
            }
        }
        
        await store.send(.startScanning) {
            $0.isScanning = true
        }
        await store.receive(.scanQualityUpdated(.good)) {
            $0.scanQuality = .good
        }
    }
    
    func testStopScanning() async {
        let store = TestStore(
            initialState: ScanningFeature.State(isScanning: true),
            reducer: ScanningFeature()
        )
        
        await store.send(.stopScanning) {
            $0.isScanning = false
        }
    }
    
    func testCaptureScan() async {
        let store = TestStore(
            initialState: ScanningFeature.State(isScanning: true),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.captureScan = { Data() }
        }
        
        await store.send(.captureButtonTapped)
        await store.receive(.scanCaptured(.success(Data()))) {
            $0.isScanning = false
        }
    }
    
    func testCaptureScanFailure() async {
        struct TestError: Error {}
        
        let store = TestStore(
            initialState: ScanningFeature.State(isScanning: true),
            reducer: ScanningFeature()
        ) {
            $0.scanningClient.captureScan = { throw TestError() }
        }
        
        await store.send(.captureButtonTapped)
        await store.receive(.scanCaptured(.failure(TestError())))
        await store.receive(.errorOccurred(.captureFailed)) {
            $0.error = .captureFailed
        }
    }
}
