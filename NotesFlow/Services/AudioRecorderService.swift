import Foundation
import AVFoundation
import Accelerate

@Observable
class AudioRecorderService: NSObject {
    var isRecording = false
    var isRecordingPaused = false
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
    var onRawMicBuffer: ((AVAudioPCMBuffer) -> Void)?
    var recordingDuration: String = "00:00"
    private var recordingStartDate: Date?
    private var meterTimer: Timer?
    
    // System Audio & Microphone capture
    private var systemAudioCapture = SystemAudioCapture()
    
    // Streaming / VAD properties
    private var audioConverter: AVAudioConverter?
    private var chunkBuffer = [Float]()
    private let sampleRate = 16000.0
    private let chunkDuration: TimeInterval = 30.0 // 30 seconds chunks
    private var maxSamplesPerChunk: Int { Int(sampleRate * chunkDuration) }
    
    // Callback for streaming chunks (VAD filtered)
    // Passes the audio data, the duration of the chunk, and whether it was classified as silence
    var onChunkReady: (([Float], TimeInterval, Bool) -> Void)?
    
    // Serial queue to protect audioFile access from the engine's audio thread
    private let audioFileQueue = DispatchQueue(label: "com.notesflow.audiofile", qos: .userInitiated)
    private var _audioFile: AVAudioFile?
    private var _audioFileConverter: AVAudioConverter?
    
    override init() {
        super.init()
    }
    
    private var wasRecordingBeforeInterrupt = false

    func startRecording() {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentPath.appendingPathComponent("NotesFlow").appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        let filename = "notesflow_" + UUID().uuidString + ".m4a"
        let audioFilename = recordingsPath.appendingPathComponent(filename)
        self.currentAudioFilePath = audioFilename.path
        
        // Reset the audio file on the serial queue
        audioFileQueue.sync {
            self._audioFile = nil
            self._audioFileConverter = nil
        }
        
        systemAudioCapture.onMixedAudioBuffer = { [weak self] buffer in
            self?.handleMixedAudioBuffer(buffer)
        }
        systemAudioCapture.onRawMicBuffer = { [weak self] buffer in
            self?.onRawMicBuffer?(buffer)
        }
        
        Task.detached {
            do {
                try await self.systemAudioCapture.start()
            } catch {
                print("SystemAudioCapture start failed: \(error)")
            }
            await MainActor.run {
                self.isRecording = true
                self.recordingInterrupted = false
                self.wasRecordingBeforeInterrupt = false
                self.recordingStartDate = Date()
                FloatingPIPManager.shared.audioService = self
                FloatingPIPManager.shared.updateVisibility()
                
                self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    self?.updateRecordingDuration()
                }
            }
        }
    }

    func stopRecording() {
        wasRecordingBeforeInterrupt = false
        Task.detached {
            // Stop capture first so no more audio buffers arrive
            try? await self.systemAudioCapture.stop()
            
            // Close the audio file safely on our serial queue, then notify
            self.audioFileQueue.sync {
                self._audioFile = nil  // Closes and finalizes the file
                self._audioFileConverter = nil
            }
            
            await MainActor.run {
                self.isRecording = false
                self.isRecordingPaused = false
                self.meterTimer?.invalidate()
                self.audioMeteringLevel = 0.0
                FloatingPIPManager.shared.updateVisibility()
                
                self.flushChunkBuffer()

                if let url = self.getRecordingURL() {
                    self.onRecordingFinished?(url)
                }
            }
        }
    }

    func pauseRecording() {
        if isRecording && !isRecordingPaused {
            isRecordingPaused = true
            meterTimer?.invalidate()
        }
    }

    func resumeRecording() {
        if isRecording && isRecordingPaused {
            isRecordingPaused = false
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.updateRecordingDuration()
            }
        }
    }

    private func handleMixedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isRecordingPaused else { return }
        
        // All audio file operations run on our serial queue to be thread-safe
        audioFileQueue.async { [weak self] in
            guard let self else { return }
            
            // Lazily create the AVAudioFile using the actual buffer format on first write
            if self._audioFile == nil, let path = self.currentAudioFilePath {
                let url = URL(fileURLWithPath: path)
                // AAC requires the file to be opened with the pcmFormatFloat32 format;
                // AVAudioFile handles the internal conversion to AAC automatically.
                let outputFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: buffer.format.sampleRate,
                    channels: buffer.format.channelCount,
                    interleaved: false
                )
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: buffer.format.channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                    AVEncoderBitRateKey: 64000
                ]
                do {
                    self._audioFile = try AVAudioFile(forWriting: url, settings: settings)
                    print("[AudioRecorder] Created audio file at \(path) with format: \(buffer.format)")
                } catch {
                    print("[AudioRecorder] Failed to create AVAudioFile: \(error)")
                    return
                }
            }
            
            guard let file = self._audioFile else { return }
            
            // If buffer format doesn't match file's processing format, convert it first
            let fileFormat = file.processingFormat
            if buffer.format != fileFormat {
                if self._audioFileConverter == nil || self._audioFileConverter?.inputFormat != buffer.format {
                    self._audioFileConverter = AVAudioConverter(from: buffer.format, to: fileFormat)
                }
                if let converter = self._audioFileConverter {
                    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * fileFormat.sampleRate / buffer.format.sampleRate)
                    if let convertedBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: max(capacity, 1)) {
                        var error: NSError?
                        var provided = false
                        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                            if provided { outStatus.pointee = .noDataNow; return nil }
                            provided = true; outStatus.pointee = .haveData; return buffer
                        }
                        if error == nil {
                            do { try file.write(from: convertedBuffer) }
                            catch { print("[AudioRecorder] Write error (converted): \(error)") }
                        }
                    }
                }
            } else {
                do { try file.write(from: buffer) }
                catch { print("[AudioRecorder] Write error: \(error)") }
            }
        }
        
        // Metering and VAD processing stay on the calling thread
        updateMetering(buffer: buffer)
        processBuffer(buffer: buffer)
    }

    private func updateRecordingDuration() {
        guard let start = recordingStartDate else { return }
        let duration = Date().timeIntervalSince(start)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        recordingDuration = String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func updateMetering(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
        let db = 20 * log10(max(rms, 0.000001))
        let minDb: Float = -80.0
        let normalized = max(0.0, (db - minDb) / (-minDb))
        DispatchQueue.main.async {
            self.audioMeteringLevel = normalized
        }
    }
    
    // MARK: - AVAudioEngine Streaming & VAD
    
    private func processBuffer(buffer: AVAudioPCMBuffer) {
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
        
        if audioConverter == nil || audioConverter?.inputFormat != buffer.format {
            audioConverter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter = audioConverter else { return }
        
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
        
        var rms: Float = 0
        vDSP_rmsqv(chunkToProcess, 1, &rms, vDSP_Length(chunkToProcess.count))
        
        let actualDuration = TimeInterval(chunkToProcess.count) / sampleRate
        let advanceDuration = keepTail ? max(0, actualDuration - tailDuration) : actualDuration
        
        // Very low threshold — only skip pure digital silence
        let thresholdRMS: Float = 0.0001
        if rms > thresholdRMS {
            // Normalize chunk to a good level for Whisper (target RMS ~0.1)
            var normalizedChunk = chunkToProcess
            let targetRMS: Float = 0.1
            if rms > 0 {
                let gain = min(targetRMS / rms, 10.0) // cap gain at 10x to avoid amplifying pure noise
                vDSP_vsmul(normalizedChunk, 1, [gain], &normalizedChunk, 1, vDSP_Length(normalizedChunk.count))
            }
            // Soft clip to [-1, 1]
            var one: Float = 1.0
            var negOne: Float = -1.0
            vDSP_vclip(normalizedChunk, 1, &negOne, &one, &normalizedChunk, 1, vDSP_Length(normalizedChunk.count))
            onChunkReady?(normalizedChunk, advanceDuration, false)
        } else {
            print("Skipped chunk (Silence, RMS: \(rms))")
            onChunkReady?([], advanceDuration, true)
        }
    }

    func getRecordingURL() -> URL? {
        guard let path = currentAudioFilePath else { return nil }
        return URL(fileURLWithPath: path)
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
            prepareAudio(for: url)
            audioPlayer?.play()
            isPlaying = true
            
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.playbackTimer?.invalidate()
                    self.currentTime = 0
                }
            }
        }
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func changeSpeed() {
        if playbackSpeed == 1.0 {
            playbackSpeed = 1.5
        } else if playbackSpeed == 1.5 {
            playbackSpeed = 2.0
        } else {
            playbackSpeed = 1.0
        }
        if isPlaying {
            audioPlayer?.rate = playbackSpeed
        }
    }
}
import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia
import Accelerate

/// Captures system audio (via SCStream) and microphone (via AVAudioEngine),
/// then delivers mixed Float32 PCM buffers via `onMixedAudioBuffer`.
class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {

    // MARK: - Output
    var onMixedAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onRawMicBuffer: ((AVAudioPCMBuffer) -> Void)?
    var isRecording = false

    // MARK: - System Audio (SCStream)
    private var stream: SCStream?
    private var systemAudioConverter: AVAudioConverter?

    // MARK: - Microphone (AVAudioEngine)
    private let micEngine = AVAudioEngine()
    private var micConverter: AVAudioConverter?

    // MARK: - Mixing
    // Common format: Float32, 48kHz stereo, non-interleaved
    private let mixFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: 48000,
                                          channels: 2,
                                          interleaved: false)!
    private let mixQueue = DispatchQueue(label: "com.notesflow.mixqueue", qos: .userInitiated)

    // FIFO buffers for system audio
    private var pendingSystemAudioLeft: [Float] = []
    private var pendingSystemAudioRight: [Float] = []
    private let pendingSystemAudioLock = NSLock()

    private var prewarmedDisplay: SCDisplay?

    override init() {
        super.init()
        Task.detached {
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
                self.prewarmedDisplay = content.displays.first
            }
        }
    }

    // MARK: - Start / Stop

    func start() async throws {
        guard !isRecording else { return }

        // Clear FIFO buffers
        pendingSystemAudioLock.lock()
        pendingSystemAudioLeft.removeAll(keepingCapacity: true)
        pendingSystemAudioRight.removeAll(keepingCapacity: true)
        pendingSystemAudioLock.unlock()

        // --- Microphone tap ---
        let inputNode = micEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }
            self.onRawMicBuffer?(buffer)
            self.mixQueue.async { self.handleMicBuffer(buffer) }
        }

        try micEngine.start()

        // --- System Audio via SCStream ---
        let display: SCDisplay
        if let d = prewarmedDisplay {
            display = d
        } else {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let d = content.displays.first else { return }
            display = d
        }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true

        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioQueue"))
        try await stream?.startCapture()

        isRecording = true
        print("[SystemAudioCapture] Started. MicFormat: \(inputFormat)")
    }

    func stop() async throws {
        isRecording = false
        try await stream?.stopCapture()
        stream = nil
        micEngine.inputNode.removeTap(onBus: 0)
        micEngine.stop()
        print("[SystemAudioCapture] Stopped.")
    }

    // MARK: - Microphone (The Clock)

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let micConverted = convertBuffer(buffer, to: mixFormat) else { return }
        let frameCount = Int(micConverted.frameLength)
        
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: mixFormat, frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        outBuffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Pull available system audio from FIFO
        pendingSystemAudioLock.lock()
        let sysAvailable = pendingSystemAudioLeft.count
        let framesToMix = min(frameCount, sysAvailable)
        
        var sysLeft = Array(pendingSystemAudioLeft.prefix(framesToMix))
        var sysRight = Array(pendingSystemAudioRight.prefix(framesToMix))
        
        pendingSystemAudioLeft.removeFirst(framesToMix)
        pendingSystemAudioRight.removeFirst(framesToMix)
        pendingSystemAudioLock.unlock()
        
        // Pad with zeros if system audio is shorter than mic buffer (e.g. no system audio playing)
        if framesToMix < frameCount {
            let padding = Array(repeating: Float(0), count: frameCount - framesToMix)
            sysLeft.append(contentsOf: padding)
            sysRight.append(contentsOf: padding)
        }
        
        // Mix!
        guard let outLeft = outBuffer.floatChannelData?[0],
              let outRight = outBuffer.floatChannelData?[1],
              let micLeft = micConverted.floatChannelData?[0] else { return }
              
        let micRight = micConverted.format.channelCount > 1 ? micConverted.floatChannelData?[1] : micLeft
        
        // Copy System Audio to Out
        cblas_scopy(Int32(frameCount), sysLeft, 1, outLeft, 1)
        cblas_scopy(Int32(frameCount), sysRight, 1, outRight, 1)
        
        // Add Mic Audio to Out
        var gain: Float = 1.0
        vDSP_vsma(micLeft, 1, &gain, outLeft, 1, outLeft, 1, vDSP_Length(frameCount))
        vDSP_vsma(micRight!, 1, &gain, outRight, 1, outRight, 1, vDSP_Length(frameCount))
        
        // Soft clip
        var one: Float = 1.0
        var negOne: Float = -1.0
        vDSP_vclip(outLeft, 1, &negOne, &one, outLeft, 1, vDSP_Length(frameCount))
        vDSP_vclip(outRight, 1, &negOne, &one, outRight, 1, vDSP_Length(frameCount))
        
        onMixedAudioBuffer?(outBuffer)
    }

    // MARK: - SCStream delegate

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isRecording else { return }
        guard let sysBuffer = pcmBuffer(from: sampleBuffer) else { return }

        mixQueue.async { [weak self] in
            guard let self, self.isRecording else { return }
            guard let sysConverted = self.convertBuffer(sysBuffer, to: self.mixFormat) else { return }
            
            guard let leftData = sysConverted.floatChannelData?[0],
                  let rightData = sysConverted.floatChannelData?[1] else { return }
                  
            let frameCount = Int(sysConverted.frameLength)
            let leftArray = Array(UnsafeBufferPointer(start: leftData, count: frameCount))
            let rightArray = Array(UnsafeBufferPointer(start: rightData, count: frameCount))
            
            self.pendingSystemAudioLock.lock()
            self.pendingSystemAudioLeft.append(contentsOf: leftArray)
            self.pendingSystemAudioRight.append(contentsOf: rightArray)
            
            // Prevent unbounded growth if mic stops for some reason (max 10 seconds buffering)
            if self.pendingSystemAudioLeft.count > 48000 * 10 {
                let excess = self.pendingSystemAudioLeft.count - 48000 * 10
                self.pendingSystemAudioLeft.removeFirst(excess)
                self.pendingSystemAudioRight.removeFirst(excess)
            }
            self.pendingSystemAudioLock.unlock()
        }
    }

    // MARK: - Helpers

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat { return buffer }

        // Reuse or create converter based on channel count (mic is usually 1, system is 2, but just use inputFormat matching)
        let converter: AVAudioConverter
        if let existing = micConverter, existing.inputFormat == buffer.format {
            converter = existing
        } else if let existing = systemAudioConverter, existing.inputFormat == buffer.format {
            converter = existing
        } else {
            guard let newConverter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }
            if micConverter == nil { micConverter = newConverter }
            else { systemAudioConverter = newConverter }
            converter = newConverter
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard capacity > 0,
              let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(capacity, 1)) else { return nil }

        var provided = false
        var convError: NSError?
        converter.convert(to: outBuf, error: &convError) { _, status in
            if provided { status.pointee = .noDataNow; return nil }
            provided = true; status.pointee = .haveData; return buffer
        }
        return convError == nil ? outBuf : nil
    }

    private func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?

        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }

        let numSamples = AVAudioFrameCount(sampleBuffer.numSamples)
        guard numSamples > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: numSamples) else { return nil }
        pcmBuffer.frameLength = numSamples

        let srcBuffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        let dstBuffers = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
        let count = min(srcBuffers.count, dstBuffers.count)
        for i in 0..<count {
            if let src = srcBuffers[i].mData, let dst = dstBuffers[i].mData {
                memcpy(dst, src, Int(srcBuffers[i].mDataByteSize))
            }
        }
        return pcmBuffer
    }
}

