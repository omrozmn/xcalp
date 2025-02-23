import Dependencies

private enum SessionManagerKey: DependencyKey {
    static let liveValue: SessionManager = .shared
}

extension DependencyValues {
    var sessionManager: SessionManager {
        get { self[SessionManagerKey.self] }
        set { self[SessionManagerKey.self] = newValue }
    }
}
