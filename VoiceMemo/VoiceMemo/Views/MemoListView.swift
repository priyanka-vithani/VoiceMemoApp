import SwiftUI

struct MemoListView: View {
    @State private var memos: [Memo] = []
    private let repository = FileVoiceMemoRepository()

    var body: some View {
        NavigationStack {
            List(memos) { memo in
                VStack(alignment: .leading, spacing: 4) {
                    Text(memo.title).font(.headline)
                    Text(memo.transcript.isEmpty ? "No transcript" : memo.transcript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .navigationTitle("Voice Memos")
            .toolbar {
                NavigationLink("Record") {
                    RecordingView()
                }
            }
            .onAppear {
                memos = repository.loadAll().sorted { $0.createdAt > $1.createdAt }
            }
        }
    }
}
