import SwiftUI
import SwiftData
import AppKit

// MARK: - App Delegate: Prevents a second window/instance on re-activation
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // Bring existing window to front instead of opening a new one
            sender.windows.first?.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return false // Do NOT create a new window
    }
}

@main
struct NotesFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Meeting.self,
            TranscriptSegment.self,
            Summary.self,
            ActionItem.self,
            Note.self,
            ChatMessage.self,
            SummaryTemplate.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @AppStorage("appAppearance") private var appAppearance: String = "System"
    @State private var audioService = AudioRecorderService()
    @State private var transcriptionService = TranscriptionService()
    @State private var aiService = AIService()
    @State private var whisperService = WhisperTranscriptionService()

    init() {
        NotificationManager.shared.requestAuthorization()
        // Migrate files to the unified dedicated directory
        AppMigrationService.shared.migrate()
        // Start meeting detection — will not show accessibility dialog (moved to Settings)
        MeetingDetectorService.shared.startMonitoring()
        // Start AppLogger session
        AppLogger.info("NotesFlow launched")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioService)
                .environment(transcriptionService)
                .environment(aiService)
                .environment(whisperService)
                .preferredColorScheme(appAppearance == "Light" ? .light : (appAppearance == "Dark" ? .dark : nil))
                .task {
                    // Pre-warm Whisper model in background so first transcription starts instantly
                    let modelId = UserDefaults.standard.string(forKey: "whisperModel") ?? "large-v3-v20240930_turbo"
                    let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let modelsDir = docPath.appendingPathComponent("NotesFlow").appendingPathComponent("Models")
                    
                    // Only pre-warm if the model directory exists (i.e. already downloaded or partially downloaded)
                    if FileManager.default.fileExists(atPath: modelsDir.path) {
                        AppLogger.transcription("Pre-warming Whisper model: \(modelId)")
                        try? await whisperService.loadModels()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 780)
        .modelContainer(sharedModelContainer)

    }
}
