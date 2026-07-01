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
    private let audioEngine = AVAudioEngine()
    
    func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                completion(authStatus == .authorized)
            }
        }
    }
    
    func startLiveTranscription(onUpdate: @escaping (String, TimeInterval) -> Void) throws {
        if let recognitionTask = recognitionTask {
            recognitionTask.cancel()
            self.recognitionTask = nil
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create SFSpeechAudioBufferRecognitionRequest")
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false
            if let result = result {
                self.currentTranscript = result.bestTranscription.formattedString
                let timestamp = Date().timeIntervalSince1970
                onUpdate(self.currentTranscript, timestamp)
                isFinal = result.isFinal
            }
            if error != nil || isFinal {
                self.audioEngine.stop()
                self.audioEngine.inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                self.isTranscribing = false
            }
        }
        
        let recordingFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        isTranscribing = true
    }
    
    func stopLiveTranscription() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isTranscribing = false
    }
    
}
