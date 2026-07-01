import Foundation

class AppMigrationService {
    static let shared = AppMigrationService()
    
    private init() {}
    
    func migrate() {
        let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let notesFlowDir = docPath.appendingPathComponent("NotesFlow")
        let recordingsDir = notesFlowDir.appendingPathComponent("Recordings")
        let modelsDir = notesFlowDir.appendingPathComponent("Models")
        
        do {
            // Create directories if they don't exist
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
            
            // Migrate existing .m4a files from Documents root
            let fileURLs = try FileManager.default.contentsOfDirectory(at: docPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            
            for fileURL in fileURLs {
                let lowercasedName = fileURL.lastPathComponent.lowercased()
                
                // Exclude files that have 'meeting' in the name as they belong to another app
                if fileURL.pathExtension.lowercased() == "m4a" && !fileURL.path.contains("/NotesFlow/") && !lowercasedName.contains("meeting") {
                    var newFilename = fileURL.lastPathComponent
                    // Add notesflow_ prefix if it doesn't have it
                    if !newFilename.hasPrefix("notesflow_") {
                        newFilename = "notesflow_" + newFilename
                    }
                    
                    let destinationURL = recordingsDir.appendingPathComponent(newFilename)
                    if !FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.moveItem(at: fileURL, to: destinationURL)
                        AppLogger.info("Migrated recording to: \(destinationURL.path)")
                    }
                }
            }
        } catch {
            AppLogger.info("Error during app migration: \(error.localizedDescription)")
        }
    }
}
