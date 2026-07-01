import Foundation
import AVFoundation

// WhisperKit and SpeakerKit imports
// These will resolve once the SPM package is added
import WhisperKit
import SpeakerKit

actor WhisperRunner {
    private let kit: WhisperKit
    init(kit: WhisperKit) { self.kit = kit }
    func transcribe(audioArray: [Float]) async throws -> [TranscriptionResult] {
        return try await kit.transcribe(audioArray: audioArray)
    }
    func transcribe(audioPath: String) async throws -> [TranscriptionResult] {
        return try await kit.transcribe(audioPath: audioPath)
    }
}

/// A service that uses WhisperKit for local transcription and SpeakerKit for speaker diarization.
/// Models are downloaded lazily on first use and cached locally.
@Observable
class WhisperTranscriptionService {
    
    // MARK: - Public State
    var isTranscribing = false
    var currentTranscribingMeetingId: UUID?
    var isModelLoaded = false
    var isDownloadingModel = false
    var modelDownloadProgress: Double = 0.0
    var statusMessage: String = ""
    
    // Chunked Transcription State
    private var cumulativeSegments: [TranscriptionSegment] = []
    private var cumulativeAudioTime: TimeInterval = 0
    private var isProcessingChunk = false
    private var chunkQueue: [(audioArray: [Float], duration: TimeInterval, isSilence: Bool)] = []
    
    init() {}
    
    // MARK: - Model Selection
    @ObservationIgnored
    var selectedModel: String {
        get { UserDefaults.standard.string(forKey: "whisperModel") ?? "base" } // Default to fast model
        set { UserDefaults.standard.set(newValue, forKey: "whisperModel") }
    }
    
    @ObservationIgnored
    var diarizationEnabled: Bool {
        get { 
            if UserDefaults.standard.object(forKey: "speakerDiarization") == nil { return true }
            return UserDefaults.standard.bool(forKey: "speakerDiarization")
        }
        set { UserDefaults.standard.set(newValue, forKey: "speakerDiarization") }
    }
    
    // MARK: - Private
    private var whisperRunner: WhisperRunner?
    private var speakerKit: SpeakerKit?
    
    // MARK: - Available Models
    static let availableModels: [(id: String, name: String, size: String)] = [
        ("tiny", "Tiny", "~75 MB"),
        ("base", "Base", "~142 MB"),
        ("small", "Small", "~466 MB"),
        ("large-v3-v20240930_turbo", "Large v3 Turbo ⭐", "~1.5 GB"),
    ]
    
    // MARK: - Load Models
    
    /// Loads WhisperKit (and optionally SpeakerKit) models.
    /// Safe to call multiple times — no-ops if already loaded.
    /// Called proactively on app launch so first transcription is instant.
    func loadModels() async throws {
        // Guard: model already loaded in this session — no re-download or re-init needed
        guard !isModelLoaded else {
            AppLogger.transcription("Model already loaded — skipping init")
            return
        }
        
        await MainActor.run {
            isDownloadingModel = true
            statusMessage = "Preparing transcription model..."
        }
        
        AppLogger.transcription("Loading WhisperKit model: \(selectedModel)")
        
        do {
            let computeOptions = ModelComputeOptions(
                melCompute: .cpuAndNeuralEngine,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            )
            
            let docPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let modelsPath = docPath.appendingPathComponent("NotesFlow").appendingPathComponent("Models")
            try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
            
            let config = WhisperKitConfig(model: selectedModel, downloadBase: modelsPath, computeOptions: computeOptions)
            let kit = try await WhisperKit(config)
            self.whisperRunner = WhisperRunner(kit: kit)
            
            if diarizationEnabled {
                await MainActor.run { statusMessage = "Preparing speaker diarization model..." }
                AppLogger.transcription("Loading SpeakerKit...")
                let sk = try await SpeakerKit()
                self.speakerKit = sk
            }
            
            await MainActor.run {
                isModelLoaded = true
                isDownloadingModel = false
                statusMessage = ""
            }
            AppLogger.transcription("Models loaded successfully")
        } catch {
            await MainActor.run {
                isDownloadingModel = false
                statusMessage = "Failed to load model: \(error.localizedDescription)"
            }
            AppLogger.transcription("Model load failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Chunked Streaming Transcription
    
    func resetTranscriptionState() {
        cumulativeSegments.removeAll()
        cumulativeAudioTime = 0
        isProcessingChunk = false
        chunkQueue.removeAll()
    }
    
    func transcribeChunk(audioArray: [Float], duration: TimeInterval, isSilence: Bool) async {
        // Enqueue the chunk to ensure we never drop audio or lose timeline synchrony
        if !audioArray.isEmpty {
            chunkQueue.append((audioArray, duration, isSilence))
        }
        
        // If we are already processing the queue, just return and let the loop handle it
        if isProcessingChunk { return }
        
        if !isModelLoaded && !isDownloadingModel {
            Task { try? await loadModels() }
        }
        
        isProcessingChunk = true
        defer { isProcessingChunk = false }
        
        while !chunkQueue.isEmpty {
            guard let runner = self.whisperRunner else {
                // Models not loaded yet, break out and wait for next trigger
                break
            }
            
            let chunk = chunkQueue.removeFirst()
            
            if chunk.isSilence {
                cumulativeAudioTime += chunk.duration
                continue
            }
            
            do {
                let transcriptionResults = try await runner.transcribe(audioArray: chunk.audioArray)
                guard let firstResult = transcriptionResults.first else {
                    cumulativeAudioTime += chunk.duration
                    continue
                }
                
                let offset = Float(cumulativeAudioTime)
                
                var newSegments = [TranscriptionSegment]()
                for segment in firstResult.segments {
                    let text = segment.text.strippingSpecialTokens().trimmingCharacters(in: .whitespacesAndNewlines)
                    if text.isEmpty { continue }
                    if segment.noSpeechProb > 0.85 { continue }
                    let alphanumericText = text.filter { $0.isLetter || $0.isNumber }
                    if alphanumericText.isEmpty { continue }
                    let uniqueChars = Set(alphanumericText.lowercased()).count
                    if uniqueChars < 4 && text.count > 10 { continue }
                    
                    // WhisperKit segments are immutable structs, we recreate them with offset times
                    let adjustedSegment = TranscriptionSegment(
                        id: segment.id,
                        seek: segment.seek,
                        start: segment.start + offset,
                        end: segment.end + offset,
                        text: segment.text,
                        tokens: segment.tokens,
                        temperature: segment.temperature,
                        avgLogprob: segment.avgLogprob,
                        compressionRatio: segment.compressionRatio,
                        noSpeechProb: segment.noSpeechProb
                    )
                    newSegments.append(adjustedSegment)
                }
                
                await MainActor.run {
                    self.cumulativeSegments.append(contentsOf: newSegments)
                }
                
                // Log chunk profiling
                let t = firstResult.timings
                AppLogger.transcription("Chunk Transcribed in \(String(format: "%.2f", t.fullPipeline))s (Dec: \(String(format: "%.2f", t.decodingLoop))s) - Tokens/sec: \(String(format: "%.2f", t.tokensPerSecond))")
                
            } catch {
                print("Error transcribing chunk: \(error)")
            }
            
            cumulativeAudioTime += chunk.duration
        }
    }
    
    // MARK: - Transcribe Audio File
    
    /// Finalizes a chunked transcription by taking the accumulated segments and optionally diarizing with SpeakerKit.
    func finishLiveTranscription(audioURL: URL) async throws -> [TranscriptSegment] {
        await MainActor.run {
            isTranscribing = true
            statusMessage = "Finalizing transcript..."
        }
        
        AppLogger.transcription("Finalizing live transcription for: \(audioURL.lastPathComponent)")
        let startTime = Date()
        
        if !isModelLoaded {
            try await loadModels()
        }
        
        // Trigger a flush of any remaining items in the chunkQueue
        if !chunkQueue.isEmpty {
            await transcribeChunk(audioArray: [], duration: 0, isSilence: true)
        }
        
        // Wait for trailing chunk to process
        while isProcessingChunk {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        
        let result = self.cumulativeSegments
        
        if result.isEmpty {
            AppLogger.transcription("No background chunks found. Falling back to full file transcription.")
            return try await transcribe(audioURL: audioURL)
        }
        
        AppLogger.transcription("Accumulated \(result.count) segments across \(cumulativeAudioTime)s of audio.")
        
        // Step 2: Optionally diarize with SpeakerKit
        let isDiarizationEnabled = self.diarizationEnabled
        let activeSpeakerKit = self.speakerKit
        
        if isDiarizationEnabled && activeSpeakerKit != nil {
            await MainActor.run {
                statusMessage = "Identifying speakers..."
            }
        }
        
        let speakerSegments = try await Task.detached {
            var segments: [DiarizedSegment] = []
            if isDiarizationEnabled, let sk = activeSpeakerKit {
                do {
                    let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
                    let diarization = try await sk.diarize(audioArray: audioArray)
                    segments = diarization.segments.map { seg in
                        DiarizedSegment(
                            speakerLabel: seg.speaker.description,
                            startTime: Double(seg.startTime),
                            endTime: Double(seg.endTime)
                        )
                    }
                } catch {
                    print("SpeakerKit diarization failed, continuing without speaker labels: \(error)")
                }
            }
            return segments
        }.value
        
        // Step 3: Align whisper segments with speaker labels
        await MainActor.run {
            statusMessage = "Finalizing transcript..."
        }
        
        let segments = await Task.detached {
            return self.alignAndMerge(
                whisperSegments: result,
                speakerSegments: speakerSegments
            )
        }.value
        
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(startTime))
        AppLogger.transcription("Live transcription complete: \(segments.count) segments in \(elapsed)")
        
        await MainActor.run {
            isTranscribing = false
            statusMessage = ""
        }
        
        return segments
    }
    
    /// Transcribes an entire audio file directly using WhisperKit. Used for uploaded files.
    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        await MainActor.run {
            isTranscribing = true
            statusMessage = "Loading models..."
        }
        
        AppLogger.transcription("Starting full transcription for: \(audioURL.lastPathComponent)")
        let startTime = Date()
        
        if !isModelLoaded {
            try await loadModels()
        }
        
        guard let runner = self.whisperRunner else {
            await MainActor.run {
                isTranscribing = false
                statusMessage = "WhisperKit not initialized"
            }
            throw TranscriptionError.modelNotLoaded
        }
        
        await MainActor.run { statusMessage = "Transcribing audio..." }
        
        let transcriptionResults = try await Task.detached {
            try await runner.transcribe(audioPath: audioURL.path)
        }.value
        
        guard let firstResult = transcriptionResults.first, !firstResult.segments.isEmpty else {
            await MainActor.run {
                isTranscribing = false
                statusMessage = ""
            }
            return []
        }
        
        let t = firstResult.timings
        AppLogger.transcription("--- WhisperKit Profiling ---")
        AppLogger.transcription("Audio Prep: \(String(format: "%.2f", t.audioProcessing))s")
        AppLogger.transcription("Encoder: \(String(format: "%.2f", t.encoding))s")
        AppLogger.transcription("Decoder: \(String(format: "%.2f", t.decodingLoop))s")
        AppLogger.transcription("Tokens/sec: \(String(format: "%.2f", t.tokensPerSecond))")
        AppLogger.transcription("Total Time: \(String(format: "%.2f", t.fullPipeline))s")
        AppLogger.transcription("----------------------------")
        
        let result = firstResult.segments
        
        var speakerSegments: [DiarizedSegment] = []
        if diarizationEnabled, let speakerKit = self.speakerKit {
            await MainActor.run { statusMessage = "Identifying speakers..." }
            do {
                let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
                let diarization = try await speakerKit.diarize(audioArray: audioArray)
                speakerSegments = diarization.segments.map { seg in
                    DiarizedSegment(
                        speakerLabel: seg.speaker.description,
                        startTime: Double(seg.startTime),
                        endTime: Double(seg.endTime)
                    )
                }
            } catch {
                print("SpeakerKit diarization failed: \(error)")
            }
        }
        
        await MainActor.run { statusMessage = "Finalizing transcript..." }
        let segments = alignAndMerge(whisperSegments: result, speakerSegments: speakerSegments)
        
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(startTime))
        AppLogger.transcription("Full transcription complete: \(segments.count) segments in \(elapsed)")
        
        await MainActor.run {
            isTranscribing = false
            statusMessage = ""
        }
        
        return segments
    }
    
    // MARK: - Alignment Logic
    
    /// Aligns WhisperKit transcription segments with SpeakerKit diarization segments,
    /// then merges consecutive segments from the same speaker into paragraphs.
    private func alignAndMerge(
        whisperSegments: [TranscriptionSegment],
        speakerSegments: [DiarizedSegment]
    ) -> [TranscriptSegment] {
        
        let filteredSegments = whisperSegments.filter { seg in
            let text = seg.text.strippingSpecialTokens().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { return false }
            if seg.noSpeechProb > 0.85 { return false }
            
            let alphanumericText = text.filter { $0.isLetter || $0.isNumber }
            if alphanumericText.isEmpty { return false }
            
            let uniqueChars = Set(alphanumericText.lowercased()).count
            if uniqueChars < 4 && text.count > 10 {
                return false
            }
            return true
        }
        
        // If no speaker segments, treat everything as single speaker
        guard !speakerSegments.isEmpty else {
            return mergeIntoSpeakerBlocks(
                filteredSegments.map { seg in
                    LabeledSegment(
                        text: seg.text.strippingSpecialTokens().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                        startTime: Double(seg.start),
                        endTime: Double(seg.end),
                        speaker: "Speaker 1"
                    )
                }
            )
        }
        
        // Assign each whisper segment to the speaker with maximum temporal overlap
        let labeled: [LabeledSegment] = filteredSegments.map { wSeg in
            let wStart = Double(wSeg.start)
            let wEnd = Double(wSeg.end)
            
            var bestSpeaker = "Speaker"
            var bestOverlap: Double = 0.0
            
            for sSeg in speakerSegments {
                let overlapStart = max(wStart, sSeg.startTime)
                let overlapEnd = min(wEnd, sSeg.endTime)
                let overlap = max(0, overlapEnd - overlapStart)
                
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    bestSpeaker = sSeg.speakerLabel
                }
            }
            
            return LabeledSegment(
                text: wSeg.text.strippingSpecialTokens().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                startTime: wStart,
                endTime: wEnd,
                speaker: formatSpeakerLabel(bestSpeaker)
            )
        }
        
        return mergeIntoSpeakerBlocks(labeled)
    }
    
    /// Merges consecutive segments from the same speaker into larger paragraph blocks.
    private func mergeIntoSpeakerBlocks(_ segments: [LabeledSegment]) -> [TranscriptSegment] {
        guard !segments.isEmpty else { return [] }
        
        var result: [TranscriptSegment] = []
        var currentSpeaker = segments[0].speaker
        var currentText = segments[0].text
        var currentStart = segments[0].startTime
        var currentEnd = segments[0].endTime
        
        for i in 1..<segments.count {
            let seg = segments[i]
            
            let timeGap = seg.startTime - currentEnd
            let isNewParagraph = (seg.speaker != currentSpeaker) || (timeGap > 1.5)
            
            if !isNewParagraph {
                // Same block — append text
                currentText += " " + seg.text
                currentEnd = seg.endTime
            } else {
                // Speaker changed or large gap — flush current block
                let ts = TranscriptSegment(
                    text: currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                    timestamp: currentStart,
                    speaker: currentSpeaker
                )
                result.append(ts)
                
                // Start new block
                currentSpeaker = seg.speaker
                currentText = seg.text
                currentStart = seg.startTime
                currentEnd = seg.endTime
            }
        }
        
        // Don't forget the last block
        let ts = TranscriptSegment(
            text: currentText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            timestamp: currentStart,
            speaker: currentSpeaker
        )
        result.append(ts)
        
        return result
    }
    
    /// Converts raw diarization labels (e.g., "SPEAKER_00") to human-readable format.
    private func formatSpeakerLabel(_ raw: String) -> String {
        if raw.hasPrefix("SPEAKER_") {
            if let numStr = raw.split(separator: "_").last, let num = Int(numStr) {
                return "Speaker \(num + 1)"
            }
        }
        return raw
    }
    
    /// Resets the loaded models (e.g., when user changes model selection in Settings).
    func resetModels() {
        whisperRunner = nil
        speakerKit = nil
        isModelLoaded = false
        statusMessage = ""
    }
}

// MARK: - Supporting Types

private struct DiarizedSegment {
    let speakerLabel: String
    let startTime: Double
    let endTime: Double
}

private struct LabeledSegment {
    let text: String
    let startTime: Double
    let endTime: Double
    let speaker: String
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Transcription model is not loaded."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}

extension String {
    func strippingSpecialTokens() -> String {
        return self.replacingOccurrences(of: "<\\|.*?\\|>", with: "", options: .regularExpression)
    }
}
