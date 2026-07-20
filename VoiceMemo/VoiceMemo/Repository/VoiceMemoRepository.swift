import Foundation

protocol VoiceMemoRepository {
    func save(_ memo: Memo) throws
    func delete(_ memo: Memo) throws
    func loadAll() -> [Memo]
}

/// Flat-file JSON index plus audio files in Documents. Fine for a
/// learning project. If this ships to real users, swap the index for
/// something that survives concurrent writes better, like Core Data
/// or SwiftData, since last-write-wins on the JSON file will bite you
/// once you add things like iCloud sync.
final class FileVoiceMemoRepository: VoiceMemoRepository {
    private let indexURL: URL
    private let documentsDirectory: URL

    init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        indexURL = documentsDirectory.appendingPathComponent("memos_index.json")
    }

    func save(_ memo: Memo) throws {
        var memos = loadAll()
        if let idx = memos.firstIndex(where: { $0.id == memo.id }) {
            memos[idx] = memo
        } else {
            memos.append(memo)
        }
        try persist(memos)
    }

    func delete(_ memo: Memo) throws {
        var memos = loadAll()
        memos.removeAll { $0.id == memo.id }
        try persist(memos)
        try? FileManager.default.removeItem(at: memo.audioFileURL)
    }

    func loadAll() -> [Memo] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([Memo].self, from: data)) ?? []
    }

    /// Moves a temp recording file into Documents so it survives app restarts.
    func permanentURL(for temporaryFile: URL) throws -> URL {
        let destination = documentsDirectory.appendingPathComponent(temporaryFile.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryFile, to: destination)
        return destination
    }

    private func persist(_ memos: [Memo]) throws {
        let data = try JSONEncoder().encode(memos)
        try data.write(to: indexURL, options: .atomic)
    }
}
