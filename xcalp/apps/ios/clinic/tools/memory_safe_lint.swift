#!/usr/bin/env swift

import Foundation

// Configuration
let batchSize = 3 // Very small batch size to prevent memory issues

func shell(_ command: String) -> String {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    try? task.run()
    task.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

// Get Swift files
print("Finding Swift files...")
let files = shell("find . -name '*.swift' -not -path './Pods/*' -not -path './build/*'")
    .components(separatedBy: .newlines)
    .filter { !$0.isEmpty }

let totalFiles = files.count
print("Found \(totalFiles) Swift files")

// Process in small batches
for (index, file) in files.enumerated() {
    print("\nProcessing file \(index + 1)/\(totalFiles): \(file)")
    
    // Run fix command for single file
    let result = shell("swiftlint --fix --quiet --path \"\(file)\"")
    if !result.isEmpty {
        print(result)
    }
    
    // Pause briefly to let memory clear
    if (index + 1) % batchSize == 0 {
        print("Pausing to clear memory...")
        Thread.sleep(forTimeInterval: 0.5)
    }
}

print("\n✅ Completed fixing all files!")
