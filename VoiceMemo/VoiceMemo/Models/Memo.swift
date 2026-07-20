import Foundation

struct Memo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var audioFileURL: URL
    var transcript: String
    var createdAt: Date
    var duration: TimeInterval

    init(
        id: UUID = UUID(),
        title: String,
        audioFileURL: URL,
        transcript: String = "",
        createdAt: Date = Date(),
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.audioFileURL = audioFileURL
        self.transcript = transcript
        self.createdAt = createdAt
        self.duration = duration
    }
}
