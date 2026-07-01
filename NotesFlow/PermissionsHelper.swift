import Foundation
import AppKit
import AVFoundation
import Speech
import ApplicationServices
import UserNotifications

class PermissionsHelper: ObservableObject {
    @Published var accessibilityGranted = false
    @Published var screenRecordingGranted = false
    @Published var microphoneGranted = false
    @Published var speechGranted = false
    @Published var notificationsGranted = false
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        // Accessibility
        accessibilityGranted = AXIsProcessTrustedWithOptions(nil)
        
        // Screen Recording
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        
        // Microphone
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        
        // Speech
        speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        
        // Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsGranted = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
    
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.checkPermissions() }
    }
    
    func openMicrophoneSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        NSWorkspace.shared.open(url)
    }
    
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { self.checkPermissions() }
        }
    }
    
    func requestSpeech() {
        SFSpeechRecognizer.requestAuthorization { _ in
            DispatchQueue.main.async { self.checkPermissions() }
        }
    }
    
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async { self.checkPermissions() }
        }
    }
    
    func resetAccessibility() {
        let process = Process()
        process.launchPath = "/usr/bin/tccutil"
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.notesflow.app"]
        try? process.run()
        process.waitUntilExit()
        checkPermissions()
    }
    
    func resetScreenRecording() {
        let process = Process()
        process.launchPath = "/usr/bin/tccutil"
        process.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.notesflow.app"]
        try? process.run()
        process.waitUntilExit()
        checkPermissions()
    }
    
    func resetMicrophone() {
        let process = Process()
        process.launchPath = "/usr/bin/tccutil"
        process.arguments = ["reset", "Microphone", Bundle.main.bundleIdentifier ?? "com.notesflow.app"]
        try? process.run()
        process.waitUntilExit()
        checkPermissions()
    }
}
