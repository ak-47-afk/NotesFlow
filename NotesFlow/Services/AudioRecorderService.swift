import Foundation
import AVFoundation
import Accelerate

@Observable
class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var isRecordingPaused = false
    var audioRecorder: AVAudioRecorder?
    var currentAudioFilePath: String?
    var audioMeteringLevel: Float = 0.0
    var recordingInterrupted = false // Banner flag for UI

    var isPlaying = false
    var audioPlayer: AVAudioPlayer?
    var playbackSpeed: Float = 1.0

    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private var playbackTimer: Timer?

    var onRecordingFinished: ((URL) -> Void)?
    var recordingDuration: String = "00:00"
    private var recordingStartDate: Date?
    private var meterTimer: Timer?
    
    // Streaming / VAD properties
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var chunkBuffer = [Float]()
    private let sampleRate = 16000.0
    private let chunkDuration: TimeInterval = 30.0 // 30 seconds chunks
    private var maxSamplesPerChunk: Int { Int(sampleRate * chunkDuration) }
    
    // Callback for streaming chunks (VAD filtered)
    // Passes the audio data, the duration of the chunk, and whether it was classified as silence
    var onChunkReady: (([Float], TimeInterval, Bool) -> Void)?
    
    override init() {
        super.init()
    }
    
    // Track whether we were mid-recording before an interruption
    private var wasRecordingBeforeInterrupt = false

    func startRecording() {
        do {
            let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentPath.appendingPathComponent("NotesFlow").appendingPathComponent("Recordings")
            try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
            let filename = "notesflow_" + UUID().uuidString + ".m4a"
            let audioFilename = recordingsPath.appendingPathComponent(filename)
            self.currentAudioFilePath = audioFilename.path

            // 16000 Hz is Whisper's native sample rate — faster transcription AND better accuracy
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                AVEncoderBitRateKey: 32000
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            isRecording = true
            recordingInterrupted = false
            wasRecordingBeforeInterrupt = false
            recordingStartDate = Date()
            FloatingPIPManager.shared.audioService = self
            FloatingPIPManager.shared.updateVisibility()

            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateMetering()
            }
            
            // Start streaming engine
            setupAudioEngineTap()
        } catch {
            print("Failed to set up recording session: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        wasRecordingBeforeInterrupt = false
        audioRecorder?.stop()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isRecording = false
        isRecordingPaused = false
        meterTimer?.invalidate()
        audioMeteringLevel = 0.0
        FloatingPIPManager.shared.updateVisibility()
        
        // Flush any remaining audio in the buffer if it contains speech
        flushChunkBuffer()

        if let url = getRecordingURL() {
            onRecordingFinished?(url)
        }
    }

    func pauseRecording() {
        if isRecording && !isRecordingPaused {
            audioRecorder?.pause()
            audioEngine.pause()
            isRecordingPaused = true
            meterTimer?.invalidate()
        }
    }

    func resumeRecording() {
        if isRecording && isRecordingPaused {
            audioRecorder?.record()
            try? audioEngine.start()
            isRecordingPaused = false
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateMetering()
            }
        }
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // If isRecording is still true, this was an unexpected stop (interruption)
        if isRecording && !flag {
            print("AudioRecorder: Unexpected stop detected — attempting auto-restart in 2 seconds")
            wasRecordingBeforeInterrupt = true
            DispatchQueue.main.async {
                self.recordingInterrupted = true
            }
            // Auto-restart after a brief pause
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self, self.wasRecordingBeforeInterrupt else { return }
                self.wasRecordingBeforeInterrupt = false
                self.resumeAfterInterruption()
            }
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("AudioRecorder encode error: \(error?.localizedDescription ?? "unknown")")
    }

    private func resumeAfterInterruption() {
        guard isRecording else { return }
        // Try to re-activate the existing recorder first
        if audioRecorder?.record() == true {
            print("AudioRecorder: Successfully resumed after interruption")
            recordingInterrupted = false
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateMetering()
            }
        } else {
            // Recorder is in a bad state — restart with a new file (append to existing via callback)
            print("AudioRecorder: Could not resume, restarting recorder")
            let oldURL = getRecordingURL()
            startRecording()
            // Notify that the old file is complete
            if let url = oldURL {
                onRecordingFinished?(url)
            }
        }
    }

    // MARK: - AVAudioEngine Streaming & VAD
    
    private func setupAudioEngineTap() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        chunkBuffer.removeAll()
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processBuffer(buffer: buffer)
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }
    
    private func processBuffer(buffer: AVAudioPCMBuffer) {
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = audioConverter else { return }
        
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        
        var error: NSError?
        var hasProvidedData = false
        converter.convert(to: convertedBuffer, error: &error, withInputFrom: { inNumPackets, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        })
        
        if error != nil { return }
        
        guard let channelData = convertedBuffer.floatChannelData else { return }
        let floats = Array(UnsafeBufferPointer(start: channelData[0], count: Int(convertedBuffer.frameLength)))
        
        chunkBuffer.append(contentsOf: floats)
        
        if chunkBuffer.count >= maxSamplesPerChunk {
            flushChunkBuffer(keepTail: true)
        }
    }
    
    private func flushChunkBuffer(keepTail: Bool = false) {
        let chunkToProcess = chunkBuffer
        
        let tailDuration: TimeInterval = 1.0
        
        if keepTail {
            // Keep the last 1 second to avoid cutting words on chunk boundaries
            let tailCount = Int(sampleRate * tailDuration)
            if chunkBuffer.count > tailCount {
                chunkBuffer = Array(chunkBuffer.suffix(tailCount))
            } else {
                chunkBuffer.removeAll(keepingCapacity: true)
            }
        } else {
            chunkBuffer.removeAll(keepingCapacity: true)
        }
        
        if chunkToProcess.isEmpty { return }
        
        // VAD (Voice Activity Detection) - Calculate RMS
        var rms: Float = 0
        vDSP_rmsqv(chunkToProcess, 1, &rms, vDSP_Length(chunkToProcess.count))
        
        let actualDuration = TimeInterval(chunkToProcess.count) / sampleRate
        // If we kept a tail, the timeline should only advance by the new, non-overlapping audio.
        let advanceDuration = keepTail ? max(0, actualDuration - tailDuration) : actualDuration
        
        let thresholdRMS: Float = 0.005 // approx -46dB
        if rms > thresholdRMS {
            onChunkReady?(chunkToProcess, advanceDuration, false)
        } else {
            print("Skipped chunk (Silence, RMS: \(rms))")
            onChunkReady?([], advanceDuration, true)
        }
    }
    
    // MARK: - Playback

    func prepareAudio(for url: URL) {
        if audioPlayer?.url != url {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                audioPlayer = player
                audioPlayer?.enableRate = true
                audioPlayer?.rate = playbackSpeed
                duration = player.duration
                currentTime = 0
                isPlaying = false
                playbackTimer?.invalidate()
            } catch {
                print("Failed to prepare audio: \(error.localizedDescription)")
            }
        }
    }

    func togglePlayback(for url: URL) {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
            playbackTimer?.invalidate()
        } else {
            if audioPlayer == nil || audioPlayer?.url != url {
                do {
                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                    audioPlayer?.enableRate = true
                    audioPlayer?.rate = playbackSpeed
                    duration = audioPlayer?.duration ?? 0
                    currentTime = 0
                } catch {
                    print("Failed to play audio: \(error.localizedDescription)")
                    return
                }
            }
            audioPlayer?.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    func changeSpeed() {
        if playbackSpeed == 1.0 {
            playbackSpeed = 1.5
        } else if playbackSpeed == 1.5 {
            playbackSpeed = 2.0
        } else if playbackSpeed == 2.0 {
            playbackSpeed = 0.5
        } else {
            playbackSpeed = 1.0
        }
        audioPlayer?.rate = playbackSpeed
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer, self.isPlaying else { return }
            self.currentTime = player.currentTime
            if !player.isPlaying {
                self.isPlaying = false
                self.playbackTimer?.invalidate()
                self.currentTime = 0
            }
        }
    }

    private func updateMetering() {
        guard let recorder = audioRecorder else { return }
        recorder.updateMeters()
        let minDb: Float = -80.0
        let db = recorder.averagePower(forChannel: 0)
        if db < minDb {
            audioMeteringLevel = 0.0
        } else if db >= 0.0 {
            audioMeteringLevel = 1.0
        } else {
            let ratio = (db - minDb) / -minDb
            audioMeteringLevel = ratio
        }

        let elapsed = recorder.currentTime
        let hours = Int(elapsed) / 3600
        let min = (Int(elapsed) % 3600) / 60
        let sec = Int(elapsed) % 60
        if hours > 0 {
            recordingDuration = String(format: "%02d:%02d:%02d", hours, min, sec)
        } else {
            recordingDuration = String(format: "%02d:%02d", min, sec)
        }
    }

    func getRecordingURL() -> URL? {
        guard let path = currentAudioFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }
}
