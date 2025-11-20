//
//  Untitled.swift
//  wakeword-ios
//
//  Created by Đoàn Văn Khoan on 20/11/25.
//

import Foundation
import AVFoundation
import CoreML



class AudioFeaturesProcessor {
    
    // CONSTANTS
    private let sampleRate = 16000 // hz
    private let melspecWindowSize = 76
    private let melspecStepSize = 8
    private let chunkSize = 1280 // 80ms at 16k Hz
    private let melspecMaxLen = 970 // 10s
    private let featureBufferMaxLen = 120
    private let maxBufferLength: Int
    
    
    
    // MODELS
    private let melspecModel: MLModel
    private let embeddingModel: MLModel
    
    
    // BUFFERS
    private var rawDataBuffer: [Int16] = []
    private var melspectrogramBuffer: [[Float]] = []
    private var featureBuffer: [[Float]] = []
    private var accumulatedSamples = 0
    private var rawDataRemainder: [Int16] = []
    
    
    init(
        melspecModelURL: URL,
        embeddingModelURL: URL
    ) throws {
        
        
        maxBufferLength = sampleRate * 10
        
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        
        
        melspecModel = try MLModel(
            contentsOf: melspecModelURL,
            configuration: config
        )
        
        embeddingModel = try MLModel(
            contentsOf: embeddingModelURL,
            configuration: config
        )
        
        melspectrogramBuffer = Array(
            repeating: Array(repeating: 1.0, count: 32),
            count: 76
        )
        
        
        let dummyAudio = (0..<sampleRate * 4).map { _ in
            Int16.random(in: -1000...1000)
        }
        featureBuffer = (try? computeEmbeddings(from: dummyAudio)) ?? []
    }
    
    
    func reset() {
        
        rawDataBuffer.removeAll()
        melspectrogramBuffer = Array(
            repeating: Array(repeating: 1.0, count: 32),
            count: 76
        )
        accumulatedSamples = 0
        rawDataRemainder.removeAll()
        
        
        let dummyAudio = (0..<sampleRate * 4).map { _ in
            Int16.random(in: -1000...1000)
        }
        featureBuffer = (try? computeEmbeddings(from: dummyAudio)) ?? []
        
    }
    
    
    func processAudioChunk(
        _ audioData: [Int16]
    ) throws -> Int {
        
        var data = rawDataRemainder.isEmpty ? audioData : rawDataRemainder + audioData
        rawDataRemainder.removeAll()
        
        var processedSamples = 0
        
        if accumulatedSamples + data.count >= chunkSize {
            let remainder = (accumulatedSamples + data.count) % chunkSize
            
            if remainder != 0 {
                
                let splitIndex = data.count - remainder
                bufferRawData( Array(data[..<splitIndex]) )
                
                accumulatedSamples += splitIndex
                rawDataRemainder = Array(data[splitIndex...])
                
            } else {
                bufferRawData(data)
                accumulatedSamples += data.count
            }
        } else {
            bufferRawData(data)
            accumulatedSamples += data.count
        }
        
        
        if (accumulatedSamples >= chunkSize)
            && (accumulatedSamples % chunkSize == 0)
        {
            
            try updateMelspectrogram(samples: accumulatedSamples)
            try updateFeatures(samples: accumulatedSamples)
            
            processedSamples = accumulatedSamples
            accumulatedSamples = 0
            
        }
        
        
        return processedSamples != 0 ? processedSamples : accumulatedSamples
    }
    
    
    
    private func bufferRawData(
        _ data: [Int16]
    ) {
        rawDataBuffer.append(contentsOf: data)
        
        if rawDataBuffer.count > maxBufferLength {
            rawDataBuffer.removeFirst(rawDataBuffer.count - maxBufferLength)
        }
    }
    
    
    // - MARK: FEATURES
    func getFeatures(
        nFeatureFrames: Int = 16
    ) -> [[Float]] {
        
        let start = max(0, featureBuffer.count - nFeatureFrames)
        return Array(featureBuffer[start...])
        
    }
    
    
    private func updateFeatures(
        samples: Int
    ) throws {
        
        let numChunks = samples / chunkSize
        
        for i in (0..<numChunks).reversed() {
            
            let index = i == 0 ? melspectrogramBuffer.count : melspectrogramBuffer.count - 8 * i
            let startIdx = max(0, index - melspecWindowSize)
            
            if index - startIdx == melspecWindowSize {
                let window = Array(melspectrogramBuffer[startIdx..<index])
                let embedding = try computeEmbeddingFromMelspec(window)
                
                featureBuffer.append(embedding)
            }
            
        }
        
        if featureBuffer.count > featureBufferMaxLen {
            featureBuffer.removeFirst(featureBuffer.count - featureBufferMaxLen)
        }
        
    }
    
    
    // - MARK: MELSPECTROGRAM
    private func updateMelspectrogram(
        samples: Int
    ) throws {
        
        guard rawDataBuffer.count >= 400 else {
            throw WakeWordError.insufficientData
        }
        
        let dataRange = rawDataBuffer.suffix(samples + 160 * 3)
        let melspec = try computeMelspectrogram(from: Array(dataRange))
        
        
        melspectrogramBuffer.append(contentsOf: melspec)
        
        if melspectrogramBuffer.count > melspecMaxLen {
            melspectrogramBuffer.removeFirst(melspectrogramBuffer.count - melspecMaxLen)
        }
    }
    
    
    private func computeMelspectrogram(
        from audio: [Int16]
    ) throws -> [[Float]] {
        
        let inputArray = try createMLMultiArray(
            shape: [1, audio.count],
            data: audio.map { Float($0) } // (-32768 → 32767) to (-1 → 1)
        )
        
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["input": inputArray]
        )
        
        // Predict
        let output = try melspecModel.prediction(from: input)
        
        
        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw WakeWordError.modelOutputError
        }
        
        let frameCount = outputArray.shape[1].intValue
        let melBins = outputArray.shape[2].intValue
        
        return (0..<frameCount).map { frame in
            
            (0..<melBins).map { bin in
                outputArray[frame * melBins + bin].floatValue / 10.0 + 2.0
            }
            
        }
        
    }
    
    
    // - MARK: EMBEDDINGS
    private func computeEmbeddings(
        from audio: [Int16]
    ) throws -> [[Float]] {
        
        let melspec = try computeMelspectrogram(from: audio)
        
        var embeddings: [[Float]] = []
        
        for i in stride(from: 0, to: melspec.count, by: melspecStepSize) {
            
            let endIdx = min(i + melspecWindowSize, melspec.count)
            
            if endIdx - i == melspecWindowSize {
                let embedding = try computeEmbeddingFromMelspec(
                    Array(melspec[i..<endIdx])
                )
                embeddings.append(embedding)
            }
            
        }
        
        return embeddings
        
    }
    
    
    private func computeEmbeddingFromMelspec(
        _ melspec: [[Float]]
    ) throws -> [Float] {
        
        let frames = melspec.count
        let melBins = melspec[0].count
        
        let inputArray = try createMLMultiArray(
            shape: [1, frames, melBins, 1],
            data: melspec.flatMap { $0 }
        )
        
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["input_1": inputArray]
        )
        
        // Predict
        let output = try embeddingModel.prediction(from: input)
        
        
        guard let outputArray = output.featureValue(for: "output")?.multiArrayValue else {
            throw WakeWordError.modelOutputError
        }
        
        
        return (0..<outputArray.count).map {
            outputArray[$0].floatValue
        }
    }
    
    
    private func createMLMultiArray(
        shape: [Int],
        data: [Float]
    ) throws -> MLMultiArray {
        
        guard let array = try? MLMultiArray(
            shape: shape as [NSNumber],
            dataType: .float32
        ) else {
            throw WakeWordError.modelInputError
        }
        
        for (i, value) in data.enumerated() {
            array[i] = NSNumber(value: value)
        }
        
        return array
        
    }
}
