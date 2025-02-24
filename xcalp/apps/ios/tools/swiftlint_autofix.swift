#!/usr/bin/env swift

import Foundation

// MARK: - Utilities

func shell(_ command: String) -> (output: String, error: String, exitCode: Int32) {
    let task = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    
    task.standardOutput = outputPipe
    task.standardError = errorPipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    
    try? task.run()
    task.waitUntilExit()
    
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    
    let output = String(data: outputData, encoding: .utf8) ?? ""
    let error = String(data: errorData, encoding: .utf8) ?? ""
    
    return (output, error, task.terminationStatus)
}

// MARK: - Main Script

print("🔍 Running SwiftLint Autocorrect...")

// First, get initial violations
let initialResult = shell("swiftlint")
let initialViolations = initialResult.output.components(separatedBy: .newlines).filter { !$0.isEmpty }

// Run autocorrect
let autocorrectResult = shell("swiftlint --fix")
print("✨ Auto-fixing violations...")

// Get remaining violations after autocorrect
let finalResult = shell("swiftlint")
let remainingViolations = finalResult.output.components(separatedBy: .newlines).filter { !$0.isEmpty }

// Calculate statistics
let initialCount = initialViolations.count
let remainingCount = remainingViolations.count
let fixedCount = initialCount - remainingCount

print("\n📊 Summary:")
print("Initial violations: \(initialCount)")
print("Automatically fixed: \(fixedCount)")
print("Remaining violations: \(remainingCount)")

if remainingCount > 0 {
    print("\n⚠️ Remaining violations that need manual attention:")
    print("Run this command to see detailed violations:")
    print("swiftlint | swift \(FileManager.default.currentDirectoryPath)/tools/analyze_issues.swift")
}

print("\n✅ Done!")
