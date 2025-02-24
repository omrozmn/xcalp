#!/usr/bin/env swift

import Foundation

enum IssueSeverity: String {
    case error = "error"
    case warning = "warning"
}

struct Issue {
    let severity: IssueSeverity
    let file: String
    let line: Int
    let message: String
    let rule: String
}

class IssueAnalyzer {
    var issues: [Issue] = []
    
    func parseSwiftLintOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.isEmpty { continue }
            
            // SwiftLint output format: file:line:col: severity: message (rule)
            let parts = line.split(separator: ":")
            guard parts.count >= 4 else { continue }
            
            let file = String(parts[0])
            guard let lineNum = Int(parts[1]) else { continue }
            
            let remaining = parts[3...].joined(separator: ":")
            let components = remaining.split(separator: "(")
            guard components.count == 2 else { continue }
            
            let message = components[0].trimmingCharacters(in: .whitespaces)
            var rule = String(components[1])
            rule = rule.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
            
            let severityString = message.split(separator: " ")[0]
            let severity = IssueSeverity(rawValue: String(severityString)) ?? .warning
            
            issues.append(Issue(
                severity: severity,
                file: file,
                line: lineNum,
                message: message,
                rule: rule
            ))
        }
    }
    
    func printSummary() {
        let errors = issues.filter { $0.severity == .error }
        let warnings = issues.filter { $0.severity == .warning }
        
        print("\n=== Issue Summary ===")
        print("Total Issues: \(issues.count)")
        print("Errors: \(errors.count)")
        print("Warnings: \(warnings.count)")
        
        if !errors.isEmpty {
            print("\nMost Common Errors:")
            printTopIssues(errors)
        }
        
        if !warnings.isEmpty {
            print("\nMost Common Warnings:")
            printTopIssues(warnings)
        }
    }
    
    private func printTopIssues(_ issues: [Issue]) {
        let ruleCount = Dictionary(grouping: issues, by: { $0.rule })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        for (rule, count) in ruleCount.prefix(5) {
            print("- \(rule): \(count) occurrences")
        }
    }
}

// Read SwiftLint output from stdin
let input = FileHandle.standardInput.availableData
let output = String(data: input, encoding: .utf8) ?? ""

let analyzer = IssueAnalyzer()
analyzer.parseSwiftLintOutput(output)
analyzer.printSummary()
