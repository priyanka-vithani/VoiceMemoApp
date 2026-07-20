import SwiftUI

struct RecordingView: View {
    @State private var viewModel: RecordingViewModel

    init() {
        let service: TranscriptionService
        if #available(iOS 26.0, *) {
            service = SpeechAnalyzerTranscriptionService()
        } else {
            // This is the seam mentioned in TranscriptionService.swift.
            // Below iOS 26, plug in a legacy SFSpeechRecognizer-based
            // implementation here instead of crashing.
            fatalError("Deployment target below iOS 26 needs a legacy TranscriptionService implementation.")
        }
        _viewModel = State(initialValue: RecordingViewModel(transcriptionService: service))
    }

    var body: some View {
        VStack(spacing: 24) {
            ScrollView {
                Text(viewModel.state.rawValue)
                    .font(.headline)
                    .padding(.top, 8)
                Text(viewModel.liveTranscript)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Button {
                Task {
                    if viewModel.isRecording {
                        await viewModel.stopRecording()
                    } else {
                        await viewModel.startRecording()
                    }
                }
            } label: {
                Image(systemName: viewModel.isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(viewModel.isRecording ? .red : .accentColor)
            }
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")
        }
        .padding()
        .navigationTitle("New Memo")
    }
}
