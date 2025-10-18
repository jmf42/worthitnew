// Logger.swift

import Foundation
import os.log // Use os.log directly as the backend

class Logger {
    static let shared = Logger() // Singleton instance
    /// Unique prefix to identify logs from this app for easy search in Console.app
    private static let searchPrefix = "[worthitapp]"
    /// Set of enabled log categories for runtime filtering
    private static var enabledCategories: Set<Category> = Set(Category.allCases)

    /// Enable only the specified categories (all others will be silenced)
    static func enable(categories: [Category]) {
        enabledCategories = Set(categories)
    }

    /// Disable the specified categories
    static func disable(categories: [Category]) {
        enabledCategories.subtract(categories)
    }

    // Publicly configurable verbosity, defaults based on build config
    static var isVerboseLoggingEnabled: Bool = {
        #if DEBUG
        return true // Enable file logging & verbose console in Debug
        #else
        return false // Disable file logging & verbose console in Release
        #endif
    }()

    private let subsystem: String
    private let categoryPrefix: String
    private let fileLogger: FileLogger?

    private init() {
        self.subsystem = AppConstants.loggerSubsystem
        self.categoryPrefix = AppConstants.loggerCategoryPrefix.isEmpty ? "worthitapp." : AppConstants.loggerCategoryPrefix

        if Self.isVerboseLoggingEnabled {
            self.fileLogger = FileLogger(subsystem: self.subsystem)
            self.oslog(.info, "Logger initialized. File logging: ENABLED. Console logging: Verbose.")
        } else {
            self.fileLogger = nil
            self.oslog(.info, "Logger initialized. File logging: DISABLED. Console logging: Standard.")
        }
    }

    enum Level: String {
        case debug    = "💬 DEBUG"    // For detailed debugging, only in DEBUG builds typically
        case info     = "ℹ️ INFO"     // Informational messages
        case notice   = "🔶 NOTICE"   // Normal but significant conditions
        case warning  = "⚠️ WARNING"  // Potential issues or unexpected events
        case error    = "🔴 ERROR"    // Errors that occurred but didn't crash
        case critical = "🚨 CRITICAL" // Critical errors, possibly leading to instability
    }

    // Internal unified logging function
    private func oslog(_ level: Level, _ message: String, _ category: Category? = nil, error: Error? = nil, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        // Skip this log if its category is currently disabled
        let resolvedCategory = category ?? .general
        guard Self.enabledCategories.contains(resolvedCategory) else { return }
        let fileName = (file as NSString).lastPathComponent
        let threadInfo = Thread.isMainThread ? "[M]" : "[B:\(qos_class_self().rawValue)]"

        var logMessage = "\(Self.searchPrefix) \(level.rawValue) [\(fileName):\(line) \(function)\(threadInfo)] \(message)"

        var allExtra = extra
        if let error = error { allExtra["error_desc"] = error.localizedDescription }
        allExtra["category"] = resolvedCategory.rawValue

        if !allExtra.isEmpty {
            let extraString = allExtra.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
            logMessage += " | { \(extraString) }"
        }

        let osLogType: OSLogType
        switch level {
        case .debug:    osLogType = .debug
        case .info:     osLogType = .info
        case .notice:   osLogType = .default // OSLog 'notice' is .default
        case .warning:  osLogType = .error   // OSLog maps warnings to .error
        case .error:    osLogType = .error
        case .critical: osLogType = .fault
        }

        let effectiveCategory = "\(categoryPrefix)\(resolvedCategory.rawValue.lowercased())"
        let customLog = OSLog(subsystem: subsystem, category: effectiveCategory)

        #if DEBUG
        if Self.isVerboseLoggingEnabled || level != .debug {
             os_log(osLogType, log: customLog, "%{public}@", logMessage)
        }
        #else
        if Self.isVerboseLoggingEnabled || (level != .debug && level != .info) {
            os_log(osLogType, log: customLog, "%{public}@", logMessage)
        }
        #endif

        fileLogger?.write(logMessage)
    }

    // Public logging methods with Category
    func debug(_ message: String, category: Category = .general, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        oslog(.debug, message, category, extra: extra, file: file, function: function, line: line)
        #endif
    }

    func info(_ message: String, category: Category = .general, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        oslog(.info, message, category, extra: extra, file: file, function: function, line: line)
    }

    func notice(_ message: String, category: Category = .general, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        oslog(.notice, message, category, extra: extra, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: Category = .general, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        oslog(.warning, message, category, extra: extra, file: file, function: function, line: line)
    }

    func error(_ message: String, category: Category = .general, error: Error? = nil, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        oslog(.error, message, category, error: error, extra: extra, file: file, function: function, line: line)
    }

    func critical(_ message: String, category: Category = .general, error: Error? = nil, extra: [String: Any] = [:], file: String = #file, function: String = #function, line: Int = #line) {
        oslog(.critical, message, category, error: error, extra: extra, file: file, function: function, line: line)
    }

    enum Category: String, CaseIterable {
        case general = "General"
        case ui = "UI"
        case lifecycle = "Lifecycle"
        case networking = "Networking"
        case services = "Services"
        case cache = "Cache"
        case parsing = "Parsing"
        case analytics = "Analytics"
        case purchase = "Purchase"
        case shareExtension = "ShareExt"
        case analysis = "Analysis"
        case timeSavings = "TimeSavings"
    }
}

private class FileLogger {
    private let logFileURL: URL?
    private let logQueue = DispatchQueue(label: "com.worthitai.fileLoggerQueue", qos: .utility)
    private let maxLogFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private let isoDateFormatter: ISO8601DateFormatter

    init?(subsystem: String) {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) else {
            os_log(OSLogType.error, log: OSLog(subsystem: subsystem, category: "FileLoggerInit"),
                   "Failed to get App Group container URL. File logging disabled.")
            return nil
        }
        let logDir = appGroupURL.appendingPathComponent("Logs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
            self.logFileURL = logDir.appendingPathComponent("WorthItAppLog.txt")
        } catch {
            os_log(OSLogType.error, log: OSLog(subsystem: subsystem, category: "FileLoggerInit"),
                   "Failed to create log directory: %{public}@. File logging disabled.", error.localizedDescription)
            return nil
        }

        self.isoDateFormatter = ISO8601DateFormatter()
        self.isoDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        rotateLogFileIfNeeded()
    }

    func write(_ message: String) {
        guard let url = logFileURL else { return }
        let timestamp = isoDateFormatter.string(from: Date())
        let logEntry = "\(timestamp) \(message)\n"

        logQueue.async {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    let fileHandle = try FileHandle(forWritingTo: url)
                    defer { fileHandle.closeFile() }
                    fileHandle.seekToEndOfFile()
                    if let data = logEntry.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                } else {
                    if let data = logEntry.data(using: .utf8) {
                        try data.write(to: url, options: .atomic)
                    }
                }
            } catch {
                 // Avoid using the main logger to log an error about itself to prevent potential loops
                print("CRITICAL FILE LOGGING ERROR: Failed to write to log file \(url.path): \(error.localizedDescription)")
            }
            self.rotateLogFileIfNeeded()
        }
    }

    private func rotateLogFileIfNeeded() {
        guard let url = logFileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? UInt64, fileSize > maxLogFileSize {
                let backupURL = url.appendingPathExtension("1")
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.moveItem(at: url, to: backupURL)
                print("INFO: Log file rotated: \(url.lastPathComponent)")
            }
        } catch {
            print("ERROR: Could not rotate log file \(url.path): \(error.localizedDescription)")
        }
    }
}
