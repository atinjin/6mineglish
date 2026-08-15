import Foundation
import SwiftData

enum TranscriptState: String, Codable {
    case none, running, ready, failed
}

@Model
final class Episode {
    @Attribute(.unique) var guid: String
    var title: String
    var summary: String
    var publishedAt: Date
    var audioURLString: String
    var pageURLString: String?
    /// 피드가 알려주는 길이. 오디오를 받고 나면 실제 값으로 덮어쓴다.
    var durationSeconds: Double

    var localAudioFilename: String?
    var transcriptStateRaw: String
    var transcriptProgress: Double

    /// 오늘 자리에 올라간 날. 하루에 한 편이라는 규칙이 이 값 하나로 굴러간다.
    var assignedDayKey: String?
    var completedAt: Date?
    var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TranscriptLine.episode)
    var lines: [TranscriptLine] = []

    init(
        guid: String,
        title: String,
        summary: String,
        publishedAt: Date,
        audioURLString: String,
        pageURLString: String? = nil,
        durationSeconds: Double = 0
    ) {
        self.guid = guid
        self.title = title
        self.summary = summary
        self.publishedAt = publishedAt
        self.audioURLString = audioURLString
        self.pageURLString = pageURLString
        self.durationSeconds = durationSeconds
        self.transcriptStateRaw = TranscriptState.none.rawValue
        self.transcriptProgress = 0
        self.addedAt = .now
    }

    var transcriptState: TranscriptState {
        get { TranscriptState(rawValue: transcriptStateRaw) ?? .none }
        set { transcriptStateRaw = newValue.rawValue }
    }

    var audioURL: URL? { URL(string: audioURLString) }
    var pageURL: URL? { pageURLString.flatMap(URL.init(string:)) }

    var localAudioURL: URL? {
        guard let localAudioFilename else { return nil }
        let url = FileVault.audioURL(localAudioFilename)
        return FileVault.exists(url) ? url : nil
    }

    var hasAudio: Bool { localAudioURL != nil }
    var hasTranscript: Bool { transcriptState == .ready && !lines.isEmpty }
    var isCompleted: Bool { completedAt != nil }

    var sortedLines: [TranscriptLine] {
        lines.sorted { $0.index < $1.index }
    }

    /// `EP.260813` — 피드 날짜에서 뽑은 짧은 표기.
    var shortCode: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyMMdd"
        return "EP." + formatter.string(from: publishedAt)
    }

    /// 파일명에 그대로 쓸 수 있게 guid를 정리한다.
    var audioFilenameCandidate: String {
        let allowed = CharacterSet.alphanumerics
        let cleaned = String(guid.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return String(cleaned.suffix(60)) + ".mp3"
    }
}

@Model
final class TranscriptLine {
    var index: Int
    var text: String
    var start: Double
    var end: Double
    /// 음성 인식이 만든 문장을 사람이 고쳤는지. 고친 문장은 재생성 때 덮어쓰지 않는다.
    var isEdited: Bool

    var episode: Episode?

    @Relationship(deleteRule: .cascade, inverse: \ShadowTake.line)
    var takes: [ShadowTake] = []

    init(index: Int, text: String, start: Double, end: Double, episode: Episode? = nil) {
        self.index = index
        self.text = text
        self.start = start
        self.end = end
        self.isEdited = false
        self.episode = episode
    }

    var duration: Double { max(0, end - start) }
    var hasTake: Bool { !takes.isEmpty }

    var latestTake: ShadowTake? {
        takes.max { $0.recordedAt < $1.recordedAt }
    }

    var sortedTakes: [ShadowTake] {
        takes.sorted { $0.recordedAt > $1.recordedAt }
    }
}

@Model
final class ShadowTake {
    @Attribute(.unique) var id: UUID
    var filename: String
    var recordedAt: Date
    var duration: Double

    var line: TranscriptLine?

    init(filename: String, duration: Double, line: TranscriptLine? = nil) {
        self.id = UUID()
        self.filename = filename
        self.recordedAt = .now
        self.duration = duration
        self.line = line
    }

    var url: URL? {
        let url = FileVault.takeURL(filename)
        return FileVault.exists(url) ? url : nil
    }
}
