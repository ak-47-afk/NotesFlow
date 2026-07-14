import SwiftUI
import SwiftData

struct FloatingRecorderView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var meeting: Meeting
    @Bindable var audioService: AudioRecorderService
    @Bindable var transcriptionService: TranscriptionService
    @Environment(WhisperTranscriptionService.self) private var whisperService
    
    @State private var isPulsing = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Recording: \(meeting.title)")
                .font(.headline)
            
            HStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 60, height: 60)
                        .scaleEffect(isPulsing ? 1.2 + CGFloat(audioService.audioMeteringLevel) : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)
                    
                    Circle()
                        .fill(Color.red)
                        .frame(width: 20, height: 20)
                }
                
                Text(transcriptionService.currentTranscript.isEmpty ? "Listening..." : transcriptionService.currentTranscript)
                    .font(.custom("JetBrainsMono-Regular", size: 14))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button(action: stopRecording) {
                Label("Stop Recording", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .frame(width: 400, height: 150)
        .background(Material.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 20)
        .onAppear {
            isPulsing = true
            
            // Reset chunked transcription state
            whisperService.resetTranscriptionState()
            
            // Wire up background chunk transcription
            audioService.onChunkReady = { [weak whisperService] chunk, duration, isSilence in
                Task {
                    await whisperService?.transcribeChunk(audioArray: chunk, duration: duration, isSilence: isSilence)
                }
            }
            
            audioService.startRecording()
            audioService.onRawMicBuffer = { buffer in
                transcriptionService.appendBuffer(buffer)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                transcriptionService.startLiveTranscription { text, timestamp in
                    DispatchQueue.main.async {
                        let segment = TranscriptSegment(text: text, timestamp: timestamp)
                        segment.meeting = meeting
                    }
                }
            }
        }
    }
    
    private func stopRecording() {
        audioService.stopRecording()
        transcriptionService.stopLiveTranscription()
        meeting.audioFilePath = audioService.currentAudioFilePath
        try? modelContext.save()
        dismiss()
    }
}
