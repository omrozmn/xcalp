import SwiftUI
import UIKit

class RTLSupportManager {
    static let shared = RTLSupportManager()
    
    private let localizationManager = LocalizationManager.shared
    private var isRTLEnabled: Bool {
        return localizationManager.getCurrentCulturalSettings().textDirection == .rightToLeft
    }
    
    // Semantic layout direction modifiers
    func applyRTLSupport<V: View>(_ view: V) -> some View {
        view.environment(\.layoutDirection, isRTLEnabled ? .rightToLeft : .leftToRight)
    }
    
    // UIKit layout support
    func configureRTLLayout(_ viewController: UIViewController) {
        viewController.view.semanticContentAttribute = isRTLEnabled ? .forceRightToLeft : .forceLeftToRight
        
        // Update navigation bar
        viewController.navigationController?.view.semanticContentAttribute = isRTLEnabled ? .forceRightToLeft : .forceLeftToRight
        viewController.navigationController?.navigationBar.semanticContentAttribute = isRTLEnabled ? .forceRightToLeft : .forceLeftToRight
    }
    
    // Layout transformation helpers
    func transformLayoutForRTL(_ frame: CGRect) -> CGRect {
        guard isRTLEnabled else { return frame }
        
        let parentWidth = UIScreen.main.bounds.width
        return CGRect(
            x: parentWidth - frame.maxX,
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }
    
    // Text alignment
    func textAlignment(default: TextAlignment = .leading) -> TextAlignment {
        return isRTLEnabled ? .trailing : `default`
    }
    
    // Image mirroring
    func shouldMirrorImage(_ type: ImageContentType) -> Bool {
        guard isRTLEnabled else { return false }
        
        switch type {
        case .directionSensitive:
            return true
        case .interface:
            return true
        case .content, .photo:
            return false
        }
    }
    
    // Gesture direction transformation
    func transformGestureDirection(_ direction: UISwipeGestureRecognizer.Direction) -> UISwipeGestureRecognizer.Direction {
        guard isRTLEnabled else { return direction }
        
        switch direction {
        case .left:
            return .right
        case .right:
            return .left
        default:
            return direction
        }
    }
}

// Supporting types
enum ImageContentType {
    case directionSensitive // Arrows, navigation icons
    case interface // UI elements
    case content // User content
    case photo // Photos
}

// SwiftUI View extension
extension View {
    func withRTLSupport() -> some View {
        RTLSupportManager.shared.applyRTLSupport(self)
    }
    
    func rtlAwareAlignment(_ alignment: TextAlignment = .leading) -> some View {
        multilineTextAlignment(RTLSupportManager.shared.textAlignment(default: alignment))
    }
    
    func rtlAwarePadding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let manager = RTLSupportManager.shared
        let isRTL = manager.isRTLEnabled
        
        return padding(
            isRTL ? edges.mirrored : edges,
            length
        )
    }
}

// Edge Set extension for RTL support
extension Edge.Set {
    var mirrored: Edge.Set {
        var result: Edge.Set = []
        if self.contains(.leading) { result.insert(.trailing) }
        if self.contains(.trailing) { result.insert(.leading) }
        if self.contains(.top) { result.insert(.top) }
        if self.contains(.bottom) { result.insert(.bottom) }
        return result
    }
}