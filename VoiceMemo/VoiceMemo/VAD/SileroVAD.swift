//
// SileroVAD.swift
//
// MVVM layer: Service
//
// Replacement for VADWrapper/RealTimeCutVADCXXLibrary using
// microsoft/onnxruntime-swift-package-manager directly.
//
// BEFORE YOU RUN THIS:
// 1. Add https://github.com/microsoft/onnxruntime-swift-package-manager via SPM.
// 2. Download silero_vad.onnx (v5) from https://github.com/snakers4/silero-vad
//    (MIT licensed) and add it to your app bundle. Do not pull the .onnx file
//    out of RealTimeCutVADLibrary's bundle, its license terms are unknown.
// 3. Open that .onnx file in https://netron.app and confirm the actual input
//    and output tensor names/shapes. The names below ("input", "state", "sr",
//    "output", "stateN") are common for Silero v5 but export versions vary.
//    If Netron shows different names, change the strings in infer(), nothing
//    else needs to change.
// 4. Confirm ORTValue/ORTSession method signatures against Xcode autocomplete
//    once the package is added — the ORT Swift API has changed across versions.
//
// Inference logic is unchanged from the original file. PCMResampler was
// moved to its own file (Services/Audio/PCMResampler.swift) since it's audio
// conversion, not VAD logic — this file should only contain VAD concerns.
//

import Foundation
import AVFoundation
import OnnxRuntimeBindings // module name may differ — check what Xcode shows after adding the package

protocol SileroVADDelegate: AnyObject {
    func vadVoiceStarted()
    func vadVoiceEnded()
}

final class SileroVAD {
    weak var delegate: SileroVADDelegate?

    // MARK: - Config
    // These match the defaults documented in your old VADWrapper.h comments.
    // Tune these once you have real audio to test against, don't trust defaults blindly.
    private let startProbThreshold: Float = 0.7
    private let endProbThreshold: Float = 0.7
    private let startFrameCount: Int = 10 // ~0.32s at 16kHz, 512-sample frames
    private let endFrameCount: Int = 57 // ~1.79s at 16kHz
    private let sampleRate: Int64 = 16_000
    private let frameSize = 512 // required window size for Silero VAD at 16kHz

    // MARK: - ONNX Runtime
    private var env: ORTEnv!
    private var session: ORTSession!
    private let contextSize = 64
    private var context = [Float](repeating: 0, count: 64)

    // MARK: - Recurrent state
    // Silero v5 carries a state tensor between calls, shape [2, 1, 128].
    // Get this wrong (skip it, reset it mid-utterance, wrong shape) and the
    // model's probabilities become meaningless after the first frame.
    private var state: [Float] = [Float](repeating: 0, count: 2 * 1 * 128)

    // MARK: - Streaming buffers
    private var pcmBuffer: [Float] = []
    private var consecutiveAbove = 0
    private var consecutiveBelow = 0
    private var isSpeaking = false

    init(modelPath: String) throws {
        env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
    }

    /// Feed mono Float32 PCM samples at 16kHz. Call continuously as audio arrives.
    /// If your source isn't 16kHz (your AudioEngineManager taps at 48kHz), resample
    /// first with PCMResampler.
    func process(samples: [Float]) {
        pcmBuffer.append(contentsOf: samples)
        while pcmBuffer.count >= frameSize {
            print("SileroVAD Processing.....")
            let frame = Array(pcmBuffer.prefix(frameSize))
            pcmBuffer.removeFirst(frameSize)
            runFrame(frame)
        }
    }

    /// Call this between separate listening sessions (e.g. after stopAndFlushNow)
    /// so leftover state doesn't bleed into a new utterance.
    func reset() {
        state = [Float](repeating: 0, count: 2 * 1 * 128)
        context = [Float](repeating: 0, count: contextSize)
        pcmBuffer.removeAll()
        consecutiveAbove = 0
        consecutiveBelow = 0
        isSpeaking = false
    }

    // MARK: - Inference

    private func runFrame(_ frame: [Float]) {
        let maxAmplitude = frame.map { abs($0) }.max() ?? 0
//        print("frame max amplitude:", maxAmplitude)

        do {
            let prob = try infer(frame: frame)
//            print("VAD prob:", prob)
            updateStateMachine(prob: prob)
        } catch {
            print("SileroVAD inference failed:", error)
        }
    }

    private func infer(frame: [Float]) throws -> Float {
        // Build the real input: 64 samples of context plus the 512 sample frame, 576 total
        var frameWithContext = context
        frameWithContext.append(contentsOf: frame)

        let inputData = NSMutableData(
            bytes: &frameWithContext,
            length: frameWithContext.count * MemoryLayout<Float>.size
        )
        let inputTensor = try ORTValue(
            tensorData: inputData,
            elementType: .float,
            shape: [1, NSNumber(value: contextSize + frameSize)]
        )

        var stateCopy = state
        let stateData = NSMutableData(
            bytes: &stateCopy,
            length: stateCopy.count * MemoryLayout<Float>.size
        )
        let stateTensor = try ORTValue(
            tensorData: stateData,
            elementType: .float,
            shape: [2, 1, 128]
        )

        // sr must be a scalar, not a 1 element array. Shape is empty, not [1].
        var sr = sampleRate
        let srData = NSMutableData(bytes: &sr, length: MemoryLayout<Int64>.size)
        let srTensor = try ORTValue(
            tensorData: srData,
            elementType: .int64,
            shape: []
        )

        let outputs = try session.run(
            withInputs: ["input": inputTensor, "state": stateTensor, "sr": srTensor],
            outputNames: ["output", "stateN"],
            runOptions: nil
        )

        guard let probValue = outputs["output"] else {
            throw NSError(domain: "SileroVAD", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing output tensor"])
        }
        let probData = try probValue.tensorData() as Data
        let prob = probData.withUnsafeBytes { $0.load(as: Float.self) }

        if let newStateValue = outputs["stateN"] {
            let newStateData = try newStateValue.tensorData() as Data
            newStateData.withUnsafeBytes { raw in
                let floatBuf = raw.bindMemory(to: Float.self)
                state = Array(floatBuf)
            }
        }

        // Save the last 64 samples of this frame as context for the next call
        context = Array(frame.suffix(contextSize))

        return prob
    }

    private func updateStateMachine(prob: Float) {
        if prob >= startProbThreshold {
            consecutiveAbove += 1
            consecutiveBelow = 0
        } else if prob < endProbThreshold {
            consecutiveBelow += 1
            consecutiveAbove = 0
        }
        // if prob falls between thresholds, leave counters as-is (hangover behavior)

        if !isSpeaking && consecutiveAbove >= startFrameCount {
            isSpeaking = true
            delegate?.vadVoiceStarted()
        }

        if isSpeaking && consecutiveBelow >= endFrameCount {
            isSpeaking = false
            delegate?.vadVoiceEnded()
        }
    }
}
