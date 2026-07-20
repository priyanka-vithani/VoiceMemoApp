import AVFoundation

/// Converts PCM buffers between formats. This is a simplified version.
/// If you hit conversion glitches on real devices, compare against
/// Apple's sample project linked from the SpeechAnalyzer WWDC session,
/// which handles more edge cases around streaming conversion.
final class BufferConverter {
    private var converter: AVAudioConverter?

    func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }

        if converter == nil || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }

        guard let converter else {
            throw TranscriptionError.invalidAudioDataType
        }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else {
            throw TranscriptionError.invalidAudioDataType
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw error
        }

        return outputBuffer
    }
}
