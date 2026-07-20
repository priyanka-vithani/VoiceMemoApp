import Speech
import AVFoundation

struct TranscriptionResult {
    let text: AttributedString
    let isFinal: Bool
}

enum TranscriptionError: Error {
    case localeNotSupported
    case failedToSetupRecognitionStream
    case invalidAudioDataType
}

/// Everything above this protocol (recording, storage, UI) doesn't care
/// which transcription engine is behind it. This is the seam you swap
/// if you ever need to support a deployment target below iOS 26 —
/// write a LegacyDictationTranscriptionService that conforms to this
/// same protocol and nothing else in the app changes.
protocol TranscriptionService: AnyObject {
    func prepare(locale: Locale) async throws
    func results() -> AsyncStream<TranscriptionResult>
    func stream(buffer: AVAudioPCMBuffer) async throws
    func finish() async throws
}

@available(iOS 26.0, macOS 26.0, *)
final class SpeechAnalyzerTranscriptionService: TranscriptionService {
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var inputSequence: AsyncStream<AnalyzerInput>?
    private var bestAudioFormat: AVAudioFormat?
    private let converter = BufferConverter()

    func prepare(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        bestAudioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        try await ensureModel(transcriber: transcriber, locale: locale)

        let (sequence, builder) = AsyncStream<AnalyzerInput>.makeStream()
        inputSequence = sequence
        inputBuilder = builder

        try await analyzer.start(inputSequence: sequence)
    }

    func results() -> AsyncStream<TranscriptionResult> {
        guard let transcriber else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(TranscriptionResult(text: result.text, isFinal: result.isFinal))
                    }
                } catch {
                    // Result stream ended, either normally or due to an error upstream.
                }
                continuation.finish()
            }
        }
    }

    func stream(buffer: AVAudioPCMBuffer) async throws {
        guard let inputBuilder, let bestAudioFormat else {
            throw TranscriptionError.invalidAudioDataType
        }
        let converted = try converter.convertBuffer(buffer, to: bestAudioFormat)
        inputBuilder.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async throws {
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        inputBuilder?.finish()
    }

    // MARK: - Model management

    private func ensureModel(transcriber: SpeechTranscriber, locale: Locale) async throws {
        guard await supported(locale: locale) else {
            throw TranscriptionError.localeNotSupported
        }
        if await installed(locale: locale) {
            return
        }
        try await downloadIfNeeded(for: transcriber)
    }

    private func supported(locale: Locale) async -> Bool {
        let supported = await SpeechTranscriber.supportedLocales
        return supported.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    private func installed(locale: Locale) async -> Bool {
        let installed = await Set(SpeechTranscriber.installedLocales)
        return installed.map { $0.identifier(.bcp47) }.contains(locale.identifier(.bcp47))
    }

    private func downloadIfNeeded(for module: SpeechTranscriber) async throws {
        if let downloader = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await downloader.downloadAndInstall()
        }
    }
}
