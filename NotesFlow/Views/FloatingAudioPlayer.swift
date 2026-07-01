import SwiftUI

struct FloatingAudioPlayer: View {
    @Bindable var meeting: Meeting
    @Bindable var audioService: AudioRecorderService
    
    var isRecording: Bool { audioService.isRecording }
    var hasAudio: Bool { meeting.audioURL != nil }
    
    var body: some View {
        if isRecording {
            HStack(spacing: 16) {
                Button(action: handleMainAction) {
                    Image(systemName: mainButtonIcon)
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
            .padding(.bottom, 20)
        } else if hasAudio {
            HStack(spacing: 16) {
                Button(action: handleMainAction) {
                    Image(systemName: mainButtonIcon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 4) {
                    ForEach(0..<12, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary)
                            .frame(width: 3, height: barHeight(for: i))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: audioService.isPlaying)
                    }
                }
                .frame(height: 24)
                
                Text(formatTime(audioService.currentTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .trailing)
                
                Slider(value: Binding(
                    get: { audioService.currentTime },
                    set: { audioService.seek(to: $0) }
                ), in: 0...(max(audioService.duration, 1.0)))
                .frame(width: 150)
                
                Text(formatTime(audioService.duration > 0 ? audioService.duration : stringToTime(meeting.duration)))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 45, alignment: .leading)
                
                Button(action: { audioService.changeSpeed() }) {
                    Text("\(String(format: "%g", audioService.playbackSpeed))x")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
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
            .padding(.bottom, 20)
            .onAppear {
                if let url = meeting.audioURL {
                    audioService.prepareAudio(for: url)
                }
            }
            .onChange(of: meeting) { _, newMeeting in
                if let url = newMeeting.audioURL {
                    audioService.prepareAudio(for: url)
                }
            }
        }
    }
    
    private var mainButtonIcon: String {
        if isRecording {
            return "stop.fill"
        } else if audioService.isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }
    
    private func handleMainAction() {
        withAnimation(.spring()) {
            if isRecording {
                audioService.stopRecording()
            } else if let url = meeting.audioURL {
                audioService.togglePlayback(for: url)
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        if isRecording {
            let base: CGFloat = 4
            let level = CGFloat(audioService.audioMeteringLevel)
            return base + CGFloat.random(in: 0...(18 * (level + 0.1)))
        } else if audioService.isPlaying {
            return CGFloat.random(in: 4...18)
        } else {
            // Static waveform pattern based on index
            let patterns: [CGFloat] = [4, 8, 14, 10, 6, 12, 16, 8, 5, 10, 15, 6]
            return patterns[index % patterns.count]
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "00:00" }
        let min = Int(time) / 60
        let sec = Int(time) % 60
        return String(format: "%02d:%02d", min, sec)
    }
    
    private func stringToTime(_ string: String) -> TimeInterval {
        let parts = string.split(separator: ":")
        guard parts.count == 2,
              let min = Double(parts[0]),
              let sec = Double(parts[1]) else { return 0 }
        return (min * 60) + sec
    }
}
