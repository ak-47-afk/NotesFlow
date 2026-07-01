import Foundation
import UserNotifications
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    private func setupCategories() {
        let startRecordingAction = UNNotificationAction(
            identifier: "START_RECORDING_ACTION",
            title: "Start Recording",
            options: .foreground
        )
        let meetingCategory = UNNotificationCategory(
            identifier: "MEETING_DETECTED_CATEGORY",
            actions: [startRecordingAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        UNUserNotificationCenter.current().setNotificationCategories([meetingCategory])
    }
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
                self.setupCategories()
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            if response.actionIdentifier == "START_RECORDING_ACTION" {
                // The user explicitly clicked the 'Start Recording' button on the notification
                NotificationCenter.default.post(name: NSNotification.Name("StartRecordingAction"), object: nil)
            }
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    func sendNotification(title: String, body: String, category: String? = nil) {
        // Only send if enabled in Settings
        // UserDefaults needs to match the @AppStorage key. By default SwiftUI @AppStorage saves to UserDefaults.standard
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category = category {
            content.categoryIdentifier = category
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending notification: \(error)")
            }
        }
    }
}
