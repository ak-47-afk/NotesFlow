import Foundation

/// Centralised file-based logger for NotesFlow.
/// Logs are written to ~/Library/Application Support/NotesFlow/logs/
/// and can be inspected to diagnose transcription and summary issues.
class AppLogger {
    static let shared = AppLogger()

    private let logDir: URL
    private let logFile: URL
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.notesflow.logger", qos: .utility)
    private var fileHandle: FileHandle?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDir = appSupport.appendingPathComponent("NotesFlow/logs", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())
        logFile = logDir.appendingPathComponent("notesflow-\(dateStr).log")

        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        // Create directory if needed
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        // Create / open log file for appending
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        write("[AppLogger] Session started. Log: \(logFile.path)")
    }

    deinit {
        fileHandle?.closeFile()
    }

    private func write(_ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let timestamp = self.dateFormatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            if let data = line.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
            print(line, terminator: "")
        }
    }

    // MARK: - Public API

    static func transcription(_ message: String) {
        shared.write("[TRANSCRIPTION] \(message)")
    }

    static func summary(_ message: String) {
        shared.write("[SUMMARY] \(message)")
    }

    static func meeting(_ message: String) {
        shared.write("[MEETING] \(message)")
    }

    static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            shared.write("[ERROR] \(message): \(error.localizedDescription)")
        } else {
            shared.write("[ERROR] \(message)")
        }
    }

    static func info(_ message: String) {
        shared.write("[INFO] \(message)")
    }

    /// Returns the path to today's log file (for display in Settings)
    static var currentLogPath: String {
        shared.logFile.path
    }

    /// Returns all log files in the log directory
    static var allLogFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: shared.logDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ).sorted { $0.lastPathComponent > $1.lastPathComponent }) ?? []
    }
}
