import ComposableArchitecture
import SwiftUI

public struct SettingsView: View {
    let store: StoreOf<SettingsFeature>
    
    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationView {
                Form {
                    Section("Profile") {
                        TextField("Name", text: viewStore.binding(
                            get: \.userProfile.name,
                            send: { .updateProfile(viewStore.userProfile.with(\.name, $0)) }
                        ))
                        
                        TextField("Email", text: viewStore.binding(
                            get: \.userProfile.email,
                            send: { .updateProfile(viewStore.userProfile.with(\.email, $0)) }
                        ))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        
                        Picker("Role", selection: viewStore.binding(
                            get: \.userProfile.role,
                            send: { .updateProfile(viewStore.userProfile.with(\.role, $0)) }
                        )) {
                            ForEach(SettingsFeature.UserRole.allCases, id: \.self) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                    }
                    
                    Section("Preferences") {
                        Toggle("Use Biometrics", isOn: viewStore.binding(
                            get: \.preferences.useBiometrics,
                            send: { .updatePreferences(viewStore.preferences.with(\.useBiometrics, $0)) }
                        ))
                        
                        Toggle("Dark Mode", isOn: viewStore.binding(
                            get: \.preferences.darkMode,
                            send: { .updatePreferences(viewStore.preferences.with(\.darkMode, $0)) }
                        ))
                        
                        Toggle("Notifications", isOn: viewStore.binding(
                            get: \.preferences.notifications,
                            send: { .updatePreferences(viewStore.preferences.with(\.notifications, $0)) }
                        ))
                    }
                    
                    Section {
                        Button("Sign Out", role: .destructive) {
                            // Handle sign out
                        }
                    }
                }
                .navigationTitle("Settings")
                .alert(
                    "Error",
                    isPresented: viewStore.binding(
                        get: { $0.errorMessage != nil },
                        send: { _ in .setError(nil) }
                    ),
                    presenting: viewStore.errorMessage
                ) { _ in
                    Button("OK") { viewStore.send(.setError(nil)) }
                } message: { message in
                    Text(message)
                }
            }
            .onAppear {
                viewStore.send(.loadSettings)
            }
        }
    }
}

extension SettingsFeature.UserProfile {
    func with<T>(_ keyPath: WritableKeyPath<Self, T>, _ value: T) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}

extension SettingsFeature.Preferences {
    func with<T>(_ keyPath: WritableKeyPath<Self, T>, _ value: T) -> Self {
        var copy = self
        copy[keyPath: keyPath] = value
        return copy
    }
}
