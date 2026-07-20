import AVFoundation

protocol AudioRecorderService: AnyObject {
    func requestPermission() async -> Bool
    func startRecording() async throws -> AsyncStream<AVAudioPCMBuffer>
    func stopRecording() async -> URL?
    var isRecording: Bool { get }
    var state: RecordingState { get }

}
enum RecordingState: String {
    case listening = "Listening for speech..."
    case recording = "Recording..."
    case processing = "Processing..."
}
/// Captures mic input, writes it to a temp file, and streams live buffers
/// to whoever wants them (in our case, the transcriber).
final class LiveAudioRecorderService: AudioRecorderService {

    private let audioEngine = AVAudioEngine()
    private var outputContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var audioFile: AVAudioFile?
    private var currentFileURL: URL?
    private(set) var state: RecordingState = .listening
    private(set) var isRecording = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() async throws -> AsyncStream<AVAudioPCMBuffer> {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("caf")
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        currentFileURL = fileURL

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.audioFile?.write(from: buffer)
            self.outputContinuation?.yield(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        return AsyncStream(AVAudioPCMBuffer.self, bufferingPolicy: .unbounded) { continuation in
            self.outputContinuation = continuation
        }
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        outputContinuation?.finish()
        outputContinuation = nil
        isRecording = false

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif

        let url = currentFileURL
        audioFile = nil
        currentFileURL = nil
        return url
    }
}
