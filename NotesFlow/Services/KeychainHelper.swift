import Foundation
import Security

final class KeychainHelper {
    static let standard = KeychainHelper()
    private init() {}
    
    func save(_ data: Data, service: String, account: String) {
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        
        var status = SecItemAdd(query, nil)
        
        if status == errSecDuplicateItem {
            let query = [
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecClass: kSecClassGenericPassword,
            ] as CFDictionary
            
            let attributesToUpdate = [kSecValueData: data] as CFDictionary
            
            status = SecItemUpdate(query, attributesToUpdate)
        }
    }
    
    func read(service: String, account: String) -> Data? {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        
        return (result as? Data)
    }
    
    func delete(service: String, account: String) {
        let query = [
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
        ] as CFDictionary
        
        SecItemDelete(query)
    }
}

extension KeychainHelper {
    func saveApiKey(_ key: String) {
        if let data = key.data(using: .utf8) {
            save(data, service: "com.notesflow.app", account: "gemini_api_key")
        }
    }
    
    func readApiKey() -> String? {
        if let data = read(service: "com.notesflow.app", account: "gemini_api_key") {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

// MARK: - AppLogger
// Inline here so it is included in the Xcode project without needing pbxproj changes.

/// Centralised file-based logger for NotesFlow.
/// Logs are written to ~/Library/Application Support/NotesFlow/logs/
final class AppLogger {
    static let shared = AppLogger()

    private let logDir: URL
    private let logFile: URL
    private let tsFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.notesflow.logger", qos: .utility)
    private var fileHandle: FileHandle?

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        logDir = appSupport.appendingPathComponent("NotesFlow/logs", isDirectory: true)

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        logFile = logDir.appendingPathComponent("notesflow-\(dayFmt.string(from: Date())).log")

        tsFormatter = DateFormatter()
        tsFormatter.dateFormat = "HH:mm:ss.SSS"

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()
        write("--- NotesFlow session started ---")
    }

    deinit { fileHandle?.closeFile() }

    private func write(_ msg: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let line = "[\(self.tsFormatter.string(from: Date()))] \(msg)\n"
            if let data = line.data(using: .utf8) { self.fileHandle?.write(data) }
        }
    }

    static func transcription(_ msg: String) { shared.write("[TRANSCRIPTION] \(msg)") }
    static func summary(_ msg: String)       { shared.write("[SUMMARY] \(msg)") }
    static func meeting(_ msg: String)       { shared.write("[MEETING] \(msg)") }
    static func info(_ msg: String)          { shared.write("[INFO] \(msg)") }
    static func error(_ msg: String, error: Error? = nil) {
        if let e = error { shared.write("[ERROR] \(msg): \(e.localizedDescription)") }
        else { shared.write("[ERROR] \(msg)") }
    }

    /// Path to today's log file (shown in Settings → Support)
    static var currentLogPath: String { shared.logFile.path }
    static var logDirectory: URL { shared.logDir }
}

