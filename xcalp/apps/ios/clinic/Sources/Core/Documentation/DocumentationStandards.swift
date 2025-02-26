import Foundation

/// DocumentationStandards defines and enforces consistent documentation practices across the codebase
struct DocumentationStandards {
    /// Required documentation sections for public APIs
    enum RequiredSection {
        case overview
        case parameters
        case returns
        case throws
        case precondition
        case postcondition
        case complexity
        case seeAlso
    }
    
    /// Defines documentation requirements for different API visibility levels
    struct VisibilityRequirements {
        let publicAPI: Set<RequiredSection> = [
            .overview, .parameters, .returns, .throws, 
            .precondition, .postcondition
        ]
        
        let internalAPI: Set<RequiredSection> = [
            .overview, .parameters, .returns, .throws
        ]
        
        let privateAPI: Set<RequiredSection> = [.overview]
    }
    
    /// Example documentation template for different types
    static let templates: [String: String] = [
        "function": """
        /// Provides a brief description of the function's purpose
        ///
        /// Detailed description of the function's behavior, including any important notes
        /// about its implementation or usage.
        ///
        /// - Parameters:
        ///   - param1: Description of first parameter
        ///   - param2: Description of second parameter
        ///
        /// - Returns: Description of the return value
        ///
        /// - Throws: Description of potential errors
        ///
        /// - Precondition: Any requirements that must be met before calling
        /// - Postcondition: Guarantees provided after successful execution
        ///
        /// - Complexity: O(n) where n is...
        ///
        /// - SeeAlso: Related functions or documentation
        """,
        
        "class": """
        /// A brief description of the class's purpose and responsibility
        ///
        /// Detailed description of the class, including:
        /// - Its role in the system
        /// - Key features and capabilities
        /// - Usage guidelines
        /// - Any important notes about thread safety or performance
        ///
        /// ## Example Usage
        /// ```swift
        /// let instance = MyClass()
        /// instance.doSomething()
        /// ```
        ///
        /// ## Topics
        /// ### Configuration
        /// - ``configure(_:)``
        /// - ``settings``
        ///
        /// ### Core Functionality
        /// - ``process(_:)``
        /// - ``validate(_:)``
        """
    ]
    
    /// Validation rules for documentation quality
    static let validationRules: [DocumentationRule] = [
        .minimumOverviewLength(words: 10),
        .requireCodeExamples(for: [.class, .protocol]),
        .requireComplexityNote(for: [.function, .method]),
        .requireThreadSafetyNote(for: [.class, .actor]),
        .requireVersionHistory
    ]
}

extension DocumentationStandards {
    /// Validates documentation for a given code element
    static func validateDocumentation(
        for element: DocumentedElement,
        documentation: String
    ) -> ValidationResult {
        var issues: [DocumentationIssue] = []
        
        // Check required sections
        let requirements = VisibilityRequirements()
        let requiredSections = requirements.sectionsFor(visibility: element.visibility)
        
        for section in requiredSections {
            if !documentation.contains(section.marker) {
                issues.append(.missingSectionError(section))
            }
        }
        
        // Apply validation rules
        for rule in validationRules {
            if !rule.validate(documentation, for: element) {
                issues.append(.ruleViolation(rule))
            }
        }
        
        return ValidationResult(
            isValid: issues.isEmpty,
            issues: issues
        )
    }
    
    /// Generates documentation template for a given element type
    static func templateFor(_ elementType: ElementType) -> String {
        return templates[elementType.rawValue] ?? ""
    }
}

// Supporting types
enum ElementType: String {
    case function
    case method
    case class
    case struct
    case protocol
    case actor
    case property
    case enumeration
}

struct DocumentedElement {
    let type: ElementType
    let name: String
    let visibility: Visibility
    let documentation: String?
}

enum Visibility {
    case `public`
    case `internal`
    case `private`
    case `fileprivate`
}

enum DocumentationRule {
    case minimumOverviewLength(words: Int)
    case requireCodeExamples(for: Set<ElementType>)
    case requireComplexityNote(for: Set<ElementType>)
    case requireThreadSafetyNote(for: Set<ElementType>)
    case requireVersionHistory
    
    func validate(_ documentation: String, for element: DocumentedElement) -> Bool {
        // Rule-specific validation logic
        switch self {
        case .minimumOverviewLength(let words):
            let wordCount = documentation.split(separator: " ").count
            return wordCount >= words
        case .requireCodeExamples(let types):
            return !types.contains(element.type) || documentation.contains("```swift")
        case .requireComplexityNote(let types):
            return !types.contains(element.type) || documentation.contains("- Complexity:")
        case .requireThreadSafetyNote(let types):
            return !types.contains(element.type) || documentation.contains("thread")
        case .requireVersionHistory:
            return documentation.contains("- Version:") || documentation.contains("## Version History")
        }
    }
}