//
//  WakeWordModel.swift
//  wakeword-ios
//
//  Created by Đoàn Văn Khoan on 20/11/25.
//



import AVFoundation
import CoreML
import Foundation


class WakeWordModel {
    
    private let model: MLModel
    private let threshold: Float
    private let featureProcessor: AudioFeaturesProcessor
    private let nFeatureFrames = 16
    private let smoothingWindow = 5
    
    
    private var recentPredictions: [Float] = []
    
    
    init(
        modelURL: URL,
        melspecModelURL: URL,
        embeddingModelURL: URL,
        threshold: Float = 0.5
    ) throws {
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        
        model = try MLModel(
            contentsOf: modelURL,
            configuration: config
        )
        
        self.threshold = threshold
        
        featureProcessor = try AudioFeaturesProcessor(
            melspecModelURL: melspecModelURL,
            embeddingModelURL: embeddingModelURL
        )
        
    }
    
    
    func reset() {
        featureProcessor.reset()
        recentPredictions.removeAll()
    }
    
    
    func processAudio(
        _ audioData: [Int16]
    ) throws -> Float? {
        
        let processedSamples = try featureProcessor.processAudioChunk(audioData)
        return processedSamples > 0 ? try predict() : nil
        
    }
    
    
    
    private func predict() throws -> Float {
        
        let features = featureProcessor.getFeatures(
            nFeatureFrames: nFeatureFrames
        )
        
        let shape = [1, nFeatureFrames, features[0].count]
        
        let flatData = features.flatMap { $0 }
        
        guard let inputArray = try? MLMultiArray(
            shape: shape as [NSNumber],
            dataType: .float32
        ) else {
            throw WakeWordError.modelInputError
        }
        
        for (i, value) in flatData.enumerated() {
            inputArray[i] = NSNumber(value: value)
        }
        
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["input": inputArray]
        )
        
        // Predict
        let output = try model.prediction(from: input)
        
        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw WakeWordError.modelOutputError
        }
        
        let score = outputArray[0].floatValue
        
        recentPredictions.append(score)
        
        
        if recentPredictions.count > smoothingWindow {
            recentPredictions.removeFirst()
        }
        
        return recentPredictions.reduce(0, +) / Float(recentPredictions.count)
    }
    
    
    func isWakeWordDetected(
        _ score: Float
    ) -> Bool {
        score >= threshold
    }
    
}
