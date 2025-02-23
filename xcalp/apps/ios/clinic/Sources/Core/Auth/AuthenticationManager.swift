import Foundation
import LocalAuthentication
import Combine
import KeychainAccess

enum AuthenticationError: Error {
    case biometricNotAvailable
    case biometricFailed
    case invalidCredentials
    case tokenExpired
    case refreshTokenExpired
    case networkError
    case encryptionError
    case unknown
}

struct TokenData: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

@MainActor
final class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var biometricType: LABiometryType = .none
    @Published private(set) var currentUserID: String?
    
    private let securityManager = SecurityManager.shared
    private let encryptionManager = EncryptionManager.shared
    private let hipaaLogger = HIPAALogger.shared
    private let context = LAContext()
    private let keychain = Keychain(service: "com.xcalp.clinic")
    
    private var cancellables = Set<AnyCancellable>()
    private let tokenRefreshInterval: TimeInterval = 3600 // 1 hour
    private let tokenRefreshThreshold: TimeInterval = 300 // 5 minutes before expiry
    
    private init() {
        checkBiometricAvailability()
        setupTokenRefresh()
    }
    
    private func checkBiometricAvailability() {
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            hipaaLogger.log(
                type: .authentication,
                action: "Biometric Check Failed",
                userID: "SYSTEM",
                details: error?.localizedDescription
            )
        }
    }
    
    private func setupTokenRefresh() {
        // Check token status every minute
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    try? await self?.handleTokenRefresh()
                }
            }
            .store(in: &cancellables)
    }
    
    private func handleTokenRefresh() async throws {
        guard let tokenData = try? getStoredTokenData() else {
            return
        }
        
        // Check if token needs refresh (5 minutes before expiry)
        let shouldRefresh = Date().addingTimeInterval(tokenRefreshThreshold) > tokenData.expiresAt
        
        if shouldRefresh {
            try await refreshToken(using: tokenData.refreshToken)
        }
    }
    
    private func refreshToken(using refreshToken: String) async throws {
        do {
            // TODO: Replace with actual API call
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            let newTokenData = TokenData(
                accessToken: UUID().uuidString,
                refreshToken: UUID().uuidString,
                expiresAt: Date().addingTimeInterval(tokenRefreshInterval)
            )
            
            try storeTokenData(newTokenData)
            
            hipaaLogger.log(
                type: .authentication,
                action: "Token Refreshed",
                userID: currentUserID ?? "UNKNOWN"
            )
        } catch {
            hipaaLogger.log(
                type: .authentication,
                action: "Token Refresh Failed",
                userID: currentUserID ?? "UNKNOWN",
                details: error.localizedDescription
            )
            throw error
        }
    }
    
    private func storeTokenData(_ tokenData: TokenData) throws {
        let data = try JSONEncoder().encode(tokenData)
        let encryptedData = try encryptionManager.encrypt(data)
        try keychain.set(encryptedData, key: "token_data")
    }
    
    private func getStoredTokenData() throws -> TokenData? {
        guard let encryptedData = try keychain.getData("token_data") else {
            return nil
        }
        
        let data = try encryptionManager.decrypt(encryptedData)
        return try JSONDecoder().decode(TokenData.self, from: data)
    }
    
    func authenticateWithBiometrics() async throws {
        guard biometricType != .none else {
            hipaaLogger.log(
                type: .authentication,
                action: "Biometric Auth Failed",
                userID: "SYSTEM",
                details: "Biometrics not available"
            )
            throw AuthenticationError.biometricNotAvailable
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Authenticate to access XcalpClinic"
            ) { [weak self] success, error in
                guard let self = self else { return }
                
                if success {
                    Task { @MainActor in
                        if let storedToken = try? self.keychain.get("auth_token") {
                            try await self.validateAndSetToken(storedToken)
                            self.hipaaLogger.log(
                                type: .authentication,
                                action: "Biometric Auth Success",
                                userID: self.currentUserID ?? "UNKNOWN"
                            )
                            continuation.resume()
                        } else {
                            self.hipaaLogger.log(
                                type: .authentication,
                                action: "Biometric Auth Failed",
                                userID: "SYSTEM",
                                details: "No stored token"
                            )
                            continuation.resume(throwing: AuthenticationError.tokenExpired)
                        }
                    }
                } else {
                    self.hipaaLogger.log(
                        type: .authentication,
                        action: "Biometric Auth Failed",
                        userID: "SYSTEM",
                        details: error?.localizedDescription
                    )
                    continuation.resume(throwing: AuthenticationError.biometricFailed)
                }
            }
        }
    }
    
    func authenticateWithCredentials(email: String, password: String) async throws {
        guard !email.isEmpty && !password.isEmpty else {
            throw AuthenticationError.invalidCredentials
        }
        
        do {
            let hashedPassword = encryptionManager.secureHash(password)
            
            // TODO: Replace with actual API authentication
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            let tokenData = TokenData(
                accessToken: UUID().uuidString,
                refreshToken: UUID().uuidString,
                expiresAt: Date().addingTimeInterval(tokenRefreshInterval)
            )
            
            try storeTokenData(tokenData)
            
            await MainActor.run {
                self.isAuthenticated = true
                self.currentUserID = email
            }
            
            hipaaLogger.log(
                type: .authentication,
                action: "Login Success",
                userID: email
            )
        } catch {
            hipaaLogger.log(
                type: .authentication,
                action: "Login Failed",
                userID: email,
                details: error.localizedDescription
            )
            throw error
        }
    }
    
    private func validateAndSetToken(_ token: String) async throws {
        // TODO: Implement actual token validation
        // For now, just check if it's not empty
        guard !token.isEmpty else {
            throw AuthenticationError.tokenExpired
        }
        
        await MainActor.run {
            self.isAuthenticated = true
        }
    }
    
    private func refreshToken() async throws {
        guard isAuthenticated else { return }
        
        // TODO: Implement actual token refresh
        // For now, just validate existing token
        if let token = try? keychain.get("auth_token") {
            try await validateAndSetToken(token)
        } else {
            throw AuthenticationError.tokenExpired
        }
    }
    
    func logout() {
        Task {
            do {
                try keychain.remove("auth_token")
                
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentUserID = nil
                }
                
                hipaaLogger.log(
                    type: .authentication,
                    action: "Logout",
                    userID: currentUserID ?? "UNKNOWN"
                )
            } catch {
                hipaaLogger.log(
                    type: .authentication,
                    action: "Logout Failed",
                    userID: currentUserID ?? "UNKNOWN",
                    details: error.localizedDescription
                )
            }
        }
    }
}
