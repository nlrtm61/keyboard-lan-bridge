import Foundation

public final class Logger {
    public enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    private let subsystem: String
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL?
    private let maxBytes: Int
    private let maxFiles: Int

    public init(subsystem: String) {
        self.subsystem = subsystem
        self.formatter = ISO8601DateFormatter()
        self.formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["KLB_LOG_PATH"], !path.isEmpty {
            self.fileURL = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        } else {
            self.fileURL = nil
        }
        self.maxBytes = Int(environment["KLB_LOG_MAX_BYTES"] ?? "") ?? 1_048_576
        self.maxFiles = max(2, Int(environment["KLB_LOG_MAX_FILES"] ?? "") ?? 5)
    }

    public func info(_ message: String) {
        log(level: .info, message: message)
    }

    public func warning(_ message: String) {
        log(level: .warning, message: message)
    }

    public func error(_ message: String) {
        log(level: .error, message: message)
    }

    private func log(level: Level, message: String) {
        lock.lock()
        defer { lock.unlock() }
        let timestamp = formatter.string(from: Date())
        let line = Data("[\(timestamp)] [\(subsystem)] [\(level.rawValue)] \(message)\n".utf8)

        if let fileURL = fileURL {
            writeToFile(line, at: fileURL)
            return
        }

        FileHandle.standardError.write(line)
    }

    private func writeToFile(_ line: Data, at url: URL) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let currentSize = ((try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue) ?? 0
        if currentSize + line.count > maxBytes {
            rotateFiles(at: url)
        }

        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            FileHandle.standardError.write(line)
            return
        }

        defer {
            try? handle.close()
        }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private func rotateFiles(at url: URL) {
        let fileManager = FileManager.default
        let oldestURL = url.appendingPathExtension("\(maxFiles)")
        if fileManager.fileExists(atPath: oldestURL.path) {
            try? fileManager.removeItem(at: oldestURL)
        }

        if maxFiles >= 2 {
            for index in stride(from: maxFiles - 1, through: 1, by: -1) {
                let source = url.appendingPathExtension("\(index)")
                let destination = url.appendingPathExtension("\(index + 1)")
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.removeItem(at: destination)
                    try? fileManager.moveItem(at: source, to: destination)
                }
            }
        }

        if fileManager.fileExists(atPath: url.path) {
            let firstRotated = url.appendingPathExtension("1")
            try? fileManager.removeItem(at: firstRotated)
            try? fileManager.moveItem(at: url, to: firstRotated)
        }
    }
}
