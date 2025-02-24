import ComposableArchitecture
import Network
@testable import XcalpClinic
import XCTest

final class NetworkSecurityTests: XCTestCase {
    func testSecureNetworkConfiguration() throws {
        let network = SecureNetworkManager.shared
        
        // Test TLS configuration
        let tlsConfig = network.getTLSConfiguration()
        XCTAssertEqual(tlsConfig.minimumTLSVersion, .TLSv12)
        XCTAssertTrue(tlsConfig.certificatePinningEnabled)
        
        // Test cipher suite configuration
        let cipherSuites = tlsConfig.allowedCipherSuites
        XCTAssertFalse(cipherSuites.contains(where: { $0.isWeak }))
        
        // Test certificate validation
        XCTAssertNoThrow(try network.validateServerCertificate())
    }
    
    func testNetworkEncryption() async throws {
        let network = SecureNetworkManager.shared
        let testData = "Sensitive Data".data(using: .utf8)!
        
        // Test data encryption for transit
        let encrypted = try await network.prepareForTransmission(data: testData)
        XCTAssertNotEqual(encrypted, testData)
        
        // Test data decryption after transit
        let decrypted = try await network.processReceivedData(encrypted)
        XCTAssertEqual(decrypted, testData)
    }
    
    func testAPIAuthentication() async throws {
        let api = SecureAPIClient.shared
        
        // Test API key validation
        XCTAssertTrue(try api.validateAPIKey())
        
        // Test request signing
        let request = try api.signRequest(
            endpoint: "test",
            method: "GET",
            body: nil
        )
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Signature"))
        
        // Test request timestamp validation
        XCTAssertTrue(try api.validateRequestTimestamp(request))
    }
    
    func testNetworkMonitoring() async throws {
        let monitor = NetworkSecurityMonitor.shared
        
        // Start monitoring
        try await monitor.startMonitoring()
        
        // Test connection security
        let connection = try await monitor.getCurrentConnection()
        XCTAssertTrue(connection.isSecure)
        
        // Test VPN detection
        let vpnStatus = try monitor.detectVPNUsage()
        XCTAssertNotNil(vpnStatus)
        
        // Test connection logging
        let logs = try monitor.getConnectionLogs()
        XCTAssertFalse(logs.isEmpty)
        
        // Stop monitoring
        monitor.stopMonitoring()
    }
    
    func testDDoSProtection() async throws {
        let protection = DDoSProtection.shared
        
        // Test rate limiting
        for _ in 1...5 {
            try await protection.recordRequest(from: "test-ip")
        }
        
        // Should be blocked after too many requests
        await XCTAssertThrowsError(try await protection.recordRequest(from: "test-ip"))
        
        // Test IP blocking
        try protection.blockIP("malicious-ip")
        XCTAssertTrue(try protection.isIPBlocked("malicious-ip"))
        
        // Test automatic unblocking after timeout
        try await Task.sleep(nanoseconds: UInt64(protection.blockDuration * 1_000_000_000))
        XCTAssertFalse(try protection.isIPBlocked("malicious-ip"))
    }
    
    func testSecureFileTransfer() async throws {
        let transfer = SecureFileTransfer.shared
        let testData = "Test File Content".data(using: .utf8)!
        
        // Test secure upload
        let uploadURL = try await transfer.uploadSecurely(
            data: testData,
            filename: "test.txt"
        )
        XCTAssertNotNil(uploadURL)
        
        // Test secure download
        let downloaded = try await transfer.downloadSecurely(from: uploadURL)
        XCTAssertEqual(downloaded, testData)
        
        // Test transfer logging
        let logs = try transfer.getTransferLogs()
        XCTAssertTrue(logs.contains { $0.filename == "test.txt" })
        
        // Test file deletion
        try await transfer.deleteSecurely(at: uploadURL)
        await XCTAssertThrowsError(try await transfer.downloadSecurely(from: uploadURL))
    }
}
