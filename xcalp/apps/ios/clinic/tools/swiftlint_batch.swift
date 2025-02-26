#!/usr/bin/env swift

import Foundation

// MARK: - Configuration
let batchSize = 5 // Reduced batch size to prevent memory issues
let currentDirectory = FileManager.default.currentDirectoryPath

// MARK: - Utilities
func shell(_ command: String) -> (output: String, exitCode: Int32) {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    
    try? task.run()
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    
    return (output, task.terminationStatus)
}

// MARK: - File Processing
func findSwiftFiles() -> [String] {
    let result = shell("find . -name '*.swift' -not -path './Pods/*' -not -path './build/*'")
    return result.output.components(separatedBy: .newlines).filter { !$0.isEmpty }
}

// MARK: - Main Process
print("🔍 Finding Swift files...")
let allFiles = findSwiftFiles()
print("Found \(allFiles.count) Swift files")

let batches = stride(from: 0, to allFiles.count, by: batchSize).map {
    Array(allFiles[$0..<min($0 + batchSize, allFiles.count)])
}

print("\nProcessing files in batches of \(batchSize)...")
var totalFixed = 0
var currentBatch = 1

for batch in batches {
    print("\n📦 Processing batch \(currentBatch)/\(batches.count)")
    
    // Process each file in the batch
    for file in batch {
        print("Fixing: \(file)")
        // First try to fix
        let fixResult = shell("swiftlint --fix --quiet --path \"\(file)\"")
        if !fixResult.output.isEmpty {
            print(fixResult.output)
        }
        
        // Check what's left
        let checkResult = shell("swiftlint lint --quiet --path \"\(file)\"")
        if !checkResult.output.isEmpty {
            print("Remaining issues in \(file):")
            print(checkResult.output)
        }
        
        if fixResult.exitCode == 0 {
            totalFixed += 1
        }
        
        // Small pause between files to prevent memory buildup
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    currentBatch += 1
    // Longer pause between batches
    print("Pausing to clear memory...")
    Thread.sleep(forTimeInterval: 1.0)
}

print("\n✅ Completed!")
print("Processed files: \(totalFixed)")
print("To check remaining issues, run:")
print("swiftlint lint --path <file_path>")