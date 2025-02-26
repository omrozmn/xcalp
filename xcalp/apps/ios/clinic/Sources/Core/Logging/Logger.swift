import Foundation
import os.log

class Logger {
    static let shared = Logger()
    private let osLog: OSLog
    private let dateFormatter: DateFormatter
    
    private init() {
        self.osLog = OSLog(subsystem: "com.xcalp.clinic", category: "default")
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        setupFileLogging()
    }
    
    private func setupFileLogging() {
        // Create logs directory if needed
        let logsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        
        try? FileManager.default.createDirectory(
            at: logsURL,
            withIntermediateDirectories: true
        )
        
        // Set up log rotation
        cleanOldLogs(in: logsURL)
    }
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .debug, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .info, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .warning, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .error, file: file, function: function, line: line)
    }
    
    func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, type: .critical, file: file, function: function, line: line)
    }
    
    private func log(_ message: String, type: LogType, file: String, function: String, line: Int) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "[\(timestamp)] [\(type.rawValue)] [\(fileName):\(line)] \(function): \(message)"
        
        // Log to console
        os_log(type.osLogType, log: osLog, "%{public}@", logMessage)
        
        // Log to file
        appendToLogFile(logMessage)
        
        // If critical, also send to analytics
        if type == .critical {
            AnalyticsService.shared.trackCriticalError(message)
        }
    }
    
    private func appendToLogFile(_ message: String) {
        let logsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs")
        
        let dateString = DateFormatter().string(from: Date())
        let logFileURL = logsURL.appendingPathComponent("xcalp_\(dateString).log")
        
        if let data = (message + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }
    
    private func cleanOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        let thirtyDaysAgo = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Date()
        ) ?? Date()
        
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }
        
        for file in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  let creationDate = attributes[.creationDate] as? Date,
                  creationDate < thirtyDaysAgo else {
                continue
            }
            
            try? fileManager.removeItem(at: file)
        }
    }
}

enum LogType: String {
    case debug = "💠 DEBUG"
    case info = "ℹ️ INFO"
    case warning = "⚠️ WARNING"
    case error = "❌ ERROR"
    case critical = "🔴 CRITICAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}