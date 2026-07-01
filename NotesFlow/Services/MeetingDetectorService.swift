import Foundation
import AppKit

class MeetingDetectorService: NSObject {
    static let shared = MeetingDetectorService()

    private var timer: Timer?
    private var detectedMeetings = [String: Date]()
    private var isMonitoringStarted = false // Prevent duplicate timers

    private let browserIdentifiers = [
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac"
    ]

    private override init() {
        super.init()
    }

    func startMonitoring() {
        let autoDetectEnabled = UserDefaults.standard.object(forKey: "autoDetectMeetings") as? Bool ?? true
        guard autoDetectEnabled else { return }
        guard !isMonitoringStarted else { return } // Prevent duplicate timers
        isMonitoringStarted = true

        // Do NOT prompt for accessibility here — that causes the OS dialog on every launch.
        // Accessibility is requested only when the user explicitly taps "Grant Access" in Settings.

        timer?.invalidate()
        // CRITICAL: dispatch all detection work off the main thread.
        // pmset, ps, and AXUIElement calls are blocking — running them on main causes the UI freeze.
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.checkForMeetings()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoringStarted = false
    }

    /// Called from Settings to prompt user once for accessibility permission.
    func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func getActiveMeetings() -> [(name: String, id: String)] {
        var activeMeetings: [(name: String, id: String)] = []
        let runningApps = NSWorkspace.shared.runningApplications
        let accessGranted = AXIsProcessTrustedWithOptions(nil)
        
        for app in runningApps {
            guard let bundleId = app.bundleIdentifier?.lowercased() else { continue }
            let localizedName = (app.localizedName ?? "").lowercased()
            
            if !accessGranted {
                // If accessibility is not granted, we try Screen Recording fallback
                let titles = getWindowTitlesFromScreenRecording()
                if !titles.isEmpty {
                    for titleStr in titles {
                        let lower = titleStr.lowercased()
                        if lower.contains("meet - ") || lower.contains("google meet") || lower.contains("meet.google") {
                            if !activeMeetings.contains(where: { $0.id == "google.meet.web" }) {
                                activeMeetings.append(("Google Meet", "google.meet.web"))
                            }
                        } else if lower.contains("microsoft teams") || lower.contains("| teams") {
                            if !activeMeetings.contains(where: { $0.id == "ms.teams.detected" }) {
                                activeMeetings.append(("Microsoft Teams", "ms.teams.detected"))
                            }
                        } else if lower.contains("zoom meeting") || lower.contains("zoom webinar") {
                            if !activeMeetings.contains(where: { $0.id == "zoom.detected" }) {
                                activeMeetings.append(("Zoom", "zoom.detected"))
                            }
                        } else if lower.contains("slack") && lower.contains("huddle") {
                            if !activeMeetings.contains(where: { $0.id == "slack.huddle.detected" }) {
                                activeMeetings.append(("Slack Huddle", "slack.huddle.detected"))
                            }
                        }
                    }
                }
                // Break out of the runningApps loop since CGWindowList covers ALL apps
                break
            }
            
            // With Accessibility, we can precisely inspect window titles to confirm an active meeting
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var windows: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windows) == .success,
                  let windowArray = windows as? [AXUIElement] else { continue }
                  
            for window in windowArray {
                var title: CFTypeRef?
                guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success,
                      let titleStr = title as? String else { continue }
                      
                let lower = titleStr.lowercased()
                
                // Detection logic
                if lower.contains("meet - ") || lower.contains("google meet") || lower.contains("meet.google") {
                    if !activeMeetings.contains(where: { $0.id == "google.meet.web" }) {
                        activeMeetings.append(("Google Meet", "google.meet.web"))
                    }
                } 
                else if lower.contains("microsoft teams") || lower.contains("| teams") {
                    let id = (bundleId.contains("teams") || bundleId.contains("msteams")) ? "ms.teams.native" : "ms.teams.web"
                    if !activeMeetings.contains(where: { $0.id == id }) {
                        activeMeetings.append(("Microsoft Teams", id))
                    }
                }
                else if lower.contains("zoom meeting") || lower.contains("zoom webinar") {
                    // "Zoom" window might just be the launcher, but "Zoom Meeting" is the active call.
                    // If it's the web version, it usually has "Zoom" in the title.
                    let id = bundleId.contains("zoom") ? "zoom.native" : "zoom.web"
                    if !activeMeetings.contains(where: { $0.id == id }) {
                        activeMeetings.append(("Zoom", id))
                    }
                }
                else if lower.contains("slack") && lower.contains("huddle") {
                    let id = bundleId.contains("slack") ? "slack.huddle.native" : "slack.huddle.web"
                    if !activeMeetings.contains(where: { $0.id == id }) {
                        activeMeetings.append(("Slack Huddle", id))
                    }
                }
            }
        }
        return activeMeetings
    }

    private func getWindowTitlesFromScreenRecording() -> [String] {
        // macOS Privacy: .optionAll redacts window titles for other apps. We MUST use .optionOnScreenOnly.
        guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return windowList.compactMap { $0[kCGWindowName as String] as? String }
    }

    // MARK: - Meeting Check Loop (runs on background thread)

    private func checkForMeetings() {
        let meetings = getActiveMeetings()
        let now = Date()

        var toNotify: [(name: String, id: String)] = []

        for meeting in meetings {
            if detectedMeetings[meeting.id] == nil {
                toNotify.append(meeting)
            }
            detectedMeetings[meeting.id] = now
        }

        for (id, lastSeen) in detectedMeetings {
            // Expire meetings not seen for 1 hour (3600 seconds) to prevent duplicate 
            // notifications when switching tabs in a browser.
            if now.timeIntervalSince(lastSeen) > 3600.0 {
                detectedMeetings.removeValue(forKey: id)
            }
        }

        // Send notifications back on main thread
        if !toNotify.isEmpty {
            DispatchQueue.main.async {
                for meeting in toNotify {
                    NotificationManager.shared.sendNotification(
                        title: "Meeting Detected",
                        body: "A \(meeting.name) meeting was detected. Would you like to record it?",
                        category: "MEETING_DETECTED_CATEGORY"
                    )
                }
            }
        }
    }
}
