import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    
    var isRecording = false
    var systemAudioURL: URL?
    private var audioFile: AVAudioFile?
    private let sampleRate = 16000.0
    private var audioConverter: AVAudioConverter?
    
    override init() {
        super.init()
    }
    
    func start() async throws -> URL? {
        guard !isRecording else { return systemAudioURL }
        
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentPath.appendingPathComponent("NotesFlow").appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let filename = "system_" + UUID().uuidString + ".m4a"
        let audioURL = recordingsPath.appendingPathComponent(filename)
        self.systemAudioURL = audioURL
        
        // Setup file writing for Whisper's native 16kHz format
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 32000
        ]
        
        audioFile = try AVAudioFile(forWriting: audioURL, settings: settings)
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return nil }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioQueue"))
        try await stream?.startCapture()
        
        isRecording = true
        return audioURL
    }
    
    func stop() async {
        isRecording = false
        try? await stream?.stopCapture()
        audioFile = nil // Close file
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isRecording else { return }
        
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
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        
        if let inputFormat = AVAudioFormat(streamDescription: asbd),
           let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) {
            
            pcmBuffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)
            
            for channel in 0..<Int(inputFormat.channelCount) {
                if let src = audioBufferList.mBuffers.mData {
                    let dst = pcmBuffer.audioBufferList.pointee.mBuffers.mData
                    memcpy(dst, src, Int(audioBufferList.mBuffers.mDataByteSize))
                }
            }
            
            // Convert to 16kHz mono for Whisper
            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false) else { return }
            
            if audioConverter == nil || audioConverter?.inputFormat != inputFormat {
                audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
            }
            
            guard let converter = audioConverter else { return }
            let capacity = AVAudioFrameCount(Double(pcmBuffer.frameLength) * sampleRate / pcmBuffer.format.sampleRate)
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
                return pcmBuffer
            })
            
            if let error = error {
                print("Audio conversion error: \(error)")
                return
            }
            
            do {
                try audioFile?.write(from: convertedBuffer)
            } catch {
                print("Error writing system audio to file: \(error)")
            }
        }
    }
}
