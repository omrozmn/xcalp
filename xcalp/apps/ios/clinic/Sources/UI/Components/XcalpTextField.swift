import SwiftUI

public struct XcalpTextField: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding()
            .background(Color(hex: "F5F5F5"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "D1D1D1"), lineWidth: 1)
            )
    }
}

extension View {
    func xcalpTextField() -> some View {
        modifier(XcalpTextField())
    }
}
