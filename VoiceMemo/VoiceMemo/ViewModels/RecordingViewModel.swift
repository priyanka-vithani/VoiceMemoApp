import Foundation
import AVFoundation
import Observation

@Observable
final class RecordingViewModel {
    var isRecording = false
    var liveTranscript: AttributedString = ""
    var errorMessage: String?
    var state: RecordingState = .listening

    private var finalizedTranscript: AttributedString = ""
    private var volatileTranscript: AttributedString = ""

    private let audioRecorder: AudioRecorderService
    private let transcriptionService: TranscriptionService
    private let repository: FileVoiceMemoRepository
    private var recognizerTask: Task<Void, Never>?
    private var streamingTask: Task<Void, Never>?

    init(
        audioRecorder: AudioRecorderService = LiveAudioRecorderService(),
        transcriptionService: TranscriptionService,
        repository: FileVoiceMemoRepository = FileVoiceMemoRepository()
    ) {
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.repository = repository
    }

    func startRecording() async {
        guard await audioRecorder.requestPermission() else {
            errorMessage = "Microphone permission denied. Enable it in Settings."
            return
        }

        do {
            try await transcriptionService.prepare(locale: Locale.current)
            let audioStream = try await audioRecorder.startRecording()

            isRecording = true
            errorMessage = nil
            finalizedTranscript = ""
            volatileTranscript = ""
            liveTranscript = ""

            recognizerTask = Task {
                for await result in transcriptionService.results() {
                    if result.isFinal {
                        finalizedTranscript += result.text
                        volatileTranscript = ""
                    } else {
                        volatileTranscript = result.text
                    }
                    liveTranscript = finalizedTranscript + volatileTranscript
                }
            }

            streamingTask = Task {
                for await buffer in audioStream {
                    try? await transcriptionService.stream(buffer: buffer)
                }
            }
        } catch {
            errorMessage = "Could not start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false

        let tempURL = await audioRecorder.stopRecording()
        try? await transcriptionService.finish()
        streamingTask?.cancel()
        recognizerTask?.cancel()

        guard let tempURL else { return }

        do {
            let permanentURL = try repository.permanentURL(for: tempURL)
            let memo = Memo(
                title: "Memo \(Date().formatted(date: .abbreviated, time: .shortened))",
                audioFileURL: permanentURL,
                transcript: String(finalizedTranscript.characters)
            )
            try repository.save(memo)
        } catch {
            errorMessage = "Could not save memo: \(error.localizedDescription)"
        }
    }
}
