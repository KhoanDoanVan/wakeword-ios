////
////  WakewordEngine.swift
////  wakeword-ios
////
////  Created by Đoàn Văn Khoan on 20/11/25.
////
//
//
//
//import CoreML
//import AVFoundation
//
//class WakewordManager {
//    
//    private var model: turn_on_the_office_lights?
//    
//    
//    private let audioEngine = AVAudioEngine()
//    private let audioQueue = DispatchQueue(label: "audio.processing.queue")
//    
//    
//    private let inputFeatureCount = 28
//    private let inputTimeSteps = 96
//    
//    
//    init() {
//        do {
//            
//            let config = MLModelConfiguration()
//            config.computeUnits = .all
//            self.model = try turn_on_the_office_lights(configuration: config)
//            
//        } catch {
//            print("Error when initialize the model: \(error)")
//        }
//    }
//    
//    
//    func startListening() {
//        
//        let inputNode = audioEngine.inputNode
//        let recordingFormat = inputNode.outputFormat(forBus: 0)
//        
//        // In general, wake word  models often be trained at 16k Hz
//        // If want to convert sample rate if settings microphone default is 44.1k Hz or 48l Hz
//        
//        // Settings Tap to get buffer of the sound continuously
//        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, time in
//            
//            self?.audioQueue.async {
//                self?.processAudioBuffer(buffer: buffer)
//            }
//            
//        }
//        
//        do {
//            try audioEngine.start()
//        } catch {
//            print("Error initialize audio engine: \(error)")
//        }
//        
//    }
//    
//    
//    private func processAudioBuffer(buffer: AVAudioPCMBuffer) {
//        
//        guard let model = self.model else { return }
//        
//        // MOST IMPORTANT STEP:
//        // Need convert sound buffer raw -> MultiArray [1, 28, 96]
//        // Depends on how you train model (MFCC or Spectrogram)
//        
//        
//        guard let inputFeatures = extractFeatures(from: buffer) else {
//            return
//        }
//        
//        do {
//            
//            // Create input for model
//            let input = turn_on_the_office_lightsInput(
//                input_1: inputFeatures
//            )
//            
//            // Predict
//            let output = try model.prediction(input: input)
//            
//            handlePredictionResult(output)
//            
//        } catch {
//            print("Error predict \(error)")
//        }
//        
//    }
//    
//    
//    // MARK: - Signal Processing (DSP)
//    private func extractFeatures(from bufffer: AVAudioPCMBuffer) -> MLMultiArray? {
//        
//        // 1. Create MLMultiArray with shape [1, 28, 96]
//        
//        guard let multiArray = try? MLMultiArray(shape: [1, 28, 96], dataType: .float32) else {
//            return nil
//        }
//        
//        // 2. Calculate MFCC / SPECTROGRAM
//        
//    }
//    
//    
//    
//    private func handlePredictionResult(_ output: MLMultiArray) {
//        
//        let score = 0.0
//        
//        if score > 0.85 {
//            print("Detected!")
//        }
//        
//    }
//    
//}
