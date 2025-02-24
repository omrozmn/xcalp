#!/usr/bin/env swift

import Foundation

// Usage: ./filter_issues.swift rule_name
// Example: swiftlint | ./filter_issues.swift implicit_return

guard CommandLine.arguments.count > 1 else {
    print("Please provide a rule name to filter by")
    exit(1)
}

let ruleToFilter = CommandLine.arguments[1]

while let line = readLine() {
    if line.contains("(\(ruleToFilter))") {
        print(line)
    }
}
