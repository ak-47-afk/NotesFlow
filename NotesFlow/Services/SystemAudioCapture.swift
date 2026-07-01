import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreMedia

class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var audioEngine = AVAudioEngine()
    private var systemAudioPlayer = AVAudioPlayerNode()
    
    var onMixedAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var isRecording = false
    
    override init() {
        super.init()
        setupEngine()
    }
    
    private func setupEngine() {
        let inputNode = audioEngine.inputNode
        let mixer = audioEngine.mainMixerNode
        
        let format = inputNode.outputFormat(forBus: 0)
        
        audioEngine.attach(systemAudioPlayer)
        audioEngine.connect(systemAudioPlayer, to: mixer, format: format)
        
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            self?.onMixedAudioBuffer?(buffer)
        }
    }
    
    func start() async throws {
        guard !isRecording else { return }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioQueue"))
        try await stream?.startCapture()
        
        try audioEngine.start()
        systemAudioPlayer.play()
        isRecording = true
    }
    
    func stop() async throws {
        isRecording = false
        try await stream?.stopCapture()
        systemAudioPlayer.stop()
        audioEngine.stop()
        audioEngine.mainMixerNode.removeTap(onBus: 0)
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
        
        if let format = AVAudioFormat(streamDescription: asbd),
           let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) {
            
            pcmBuffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)
            
            for channel in 0..<Int(format.channelCount) {
                if let src = audioBufferList.mBuffers.mData {
                    let dst = pcmBuffer.audioBufferList.pointee.mBuffers.mData
                    memcpy(dst, src, Int(audioBufferList.mBuffers.mDataByteSize))
                }
            }
            
            systemAudioPlayer.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
    }
}
