import Foundation
import Speech

@Observable
class TranscriptionService {
    var isTranscribing = false
    var currentTranscribingMeetingId: UUID?
    var currentTranscript: String = ""
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                completion(authStatus == .authorized)
            }
        }
    }
    
    /// Start live transcription using externally-provided audio buffers.
    /// Call `appendBuffer(_:)` to feed audio data from any source (e.g. the mic tap in SystemAudioCapture).
    /// This does NOT create its own AVAudioEngine, eliminating hardware contention.
    func startLiveTranscription(onUpdate: @escaping (String, TimeInterval) -> Void) {
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            print("Unable to create SFSpeechAudioBufferRecognitionRequest")
            return
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            var isFinal = false
            if let result = result {
                let text = result.bestTranscription.formattedString
                let timestamp = Date().timeIntervalSince1970
                DispatchQueue.main.async {
                    self.currentTranscript = text
                    onUpdate(text, timestamp)
                }
                isFinal = result.isFinal
            }
            if error != nil || isFinal {
                DispatchQueue.main.async {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isTranscribing = false
                }
            }
        }
        
        DispatchQueue.main.async {
            self.isTranscribing = true
        }
    }
    
    /// Feed an audio buffer from an external source into the speech recognizer.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    func stopLiveTranscription() {
        recognitionRequest?.endAudio()
        DispatchQueue.main.async {
            self.isTranscribing = false
        }
    }
    
}
