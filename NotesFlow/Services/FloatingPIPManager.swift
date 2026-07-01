import SwiftUI
import AppKit

class FloatingPIPManager: NSObject, NSWindowDelegate {
    static let shared = FloatingPIPManager()
    
    private var pipWindow: NSPanel?
    var audioService: AudioRecorderService?
    
    private override init() {
        super.init()
        setupObservers()
    }
    
    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleAppActivation), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppActivation), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppActivation), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    
    func showPIP(audioService: AudioRecorderService) {
        self.audioService = audioService
        
        if pipWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
                styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
                backing: .buffered,
                defer: false
            )
            
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.backgroundColor = NSColor.clear
            panel.hasShadow = true
            panel.delegate = self
            
            let pipView = PIPRecordingView(audioService: audioService)
                .frame(width: 260, height: 60, alignment: .trailing)
            let hostingView = NSHostingView(rootView: pipView)
            hostingView.autoresizingMask = [.width, .height]
            panel.contentView = hostingView
            
            // Initial position (top right corner of the screen)
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.maxX - 280
                let y = screen.visibleFrame.maxY - 80
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            
            self.pipWindow = panel
        }
        
        pipWindow?.orderFront(nil)
    }
    
    func hidePIP() {
        pipWindow?.orderOut(nil)
    }
    
    func updateVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let audioService = self.audioService, audioService.isRecording else {
                self.hidePIP()
                return
            }
            
            let isMyAppActive = NSApplication.shared.isActive
            if isMyAppActive {
                self.hidePIP()
            } else {
                self.showPIP(audioService: audioService)
            }
        }
    }
    
    @objc private func handleAppActivation(notification: Notification) {
        updateVisibility()
    }
}

struct PIPRecordingView: View {
    @Bindable var audioService: AudioRecorderService
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle grid
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                }
                HStack(spacing: 3) {
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                }
                HStack(spacing: 3) {
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                    Circle().fill(Color.gray.opacity(0.6)).frame(width: 3, height: 3)
                }
            }
            .padding(.trailing, 4)
            
            if isHovering {
                Button(action: {
                    audioService.stopRecording()
                    FloatingPIPManager.shared.hidePIP()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if audioService.isRecordingPaused {
                        audioService.resumeRecording()
                    } else {
                        audioService.pauseRecording()
                    }
                }) {
                    Image(systemName: audioService.isRecordingPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 4) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.red)
                        .frame(width: 3, height: barHeight(for: i))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioService.audioMeteringLevel)
                }
            }
            .frame(height: 24)
            
            Text(audioService.recordingDuration)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 4)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hovering
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        if !audioService.isRecordingPaused {
            let base: CGFloat = 4
            let level = CGFloat(audioService.audioMeteringLevel)
            return base + CGFloat.random(in: 0...(18 * (level + 0.1)))
        } else {
            return 4
        }
    }
}
