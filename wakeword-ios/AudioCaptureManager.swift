//
//  AudioCaptureManager.swift
//  wakeword-ios
//
//  Created by Đoàn Văn Khoan on 21/11/25.
//


import AVFoundation
import CoreML
import Foundation


class AudioCaptureManager: NSObject {
    
    private let audioEngine = AVAudioEngine()
    private let wakeWordModel: WakeWordModel
    private var onWakeWordDetected: ((Float) -> Void)?
    
    
    init(
        wakeWordModel: WakeWordModel
    ) {
        self.wakeWordModel = wakeWordModel
        super.init()
    }
    
    
    func startListening(
        onWakeWordDetected: @escaping (Float) -> Void
    ) throws{
        
        self.onWakeWordDetected = onWakeWordDetected
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1280,
            format: recordingFormat
        ) { [weak self] buffer, _ in
            
            self?.processAudioBuffer(buffer)
            
        }
        
        audioEngine.prepare()
        
        try audioEngine.start()
        
    }
    
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        wakeWordModel.reset()
    }
    
    
    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer
    ) {
        
        guard let channelData = buffer.int16ChannelData else { return }
        
        let samples = Array(
            UnsafeBufferPointer(
                start: channelData[0],
                count: Int(buffer.frameLength)
            )
        )
        
        do {
            
            if let score = try wakeWordModel.processAudio(samples),
               wakeWordModel.isWakeWordDetected(score)
            {
                
                DispatchQueue.main.async {
                    self.onWakeWordDetected?(score)
                }
                
            }
            
        } catch {
            print("Error processing audio: \(error)")
        }
        
    }
    
}
