import Foundation
import SwiftData

/// 한 단어에서 세 장이 나온다. 알아듣는 것과 꺼내 쓰는 것은 같이 늘지 않으므로 간격을 따로 센다.
enum CardKind: String, Codable, CaseIterable, Identifiable {
    case sentence
    case wordRecognition
    case wordProduction
    case wordListening

    var id: String { rawValue }

    var isWord: Bool { self != .sentence }

    var label: String {
        switch self {
        case .sentence: "문장"
        case .wordRecognition, .wordProduction, .wordListening: "단어"
        }
    }

    var directionLabel: String {
        switch self {
        case .sentence: "문장 · 한국어 → 영어"
        case .wordRecognition: "단어 · 영어 → 뜻"
        case .wordProduction: "단어 · 뜻 → 영어"
        case .wordListening: "단어 · 듣고 맞히기"
        }
    }

    /// 앞면에 글자를 보여주지 않고 소리만 내는 방향.
    var isAudioPrompt: Bool { self == .wordListening }
}

@Model
final class StudyCard {
    @Attribute(.unique) var id: UUID
    var kindRaw: String

    /// 앞면 텍스트. `wordListening`이면 비어 있고 대신 구간 오디오를 재생한다.
    var prompt: String
    var answer: String
    /// 품사나 짧은 설명.
    var note: String
    /// 에피소드 원문 그대로. 지어내지 않는다.
    var example: String

    var episodeGUID: String?
    var lineIndex: Int?
    var audioStart: Double?
    var audioEnd: Double?
    var takeFilename: String?

    /// 같은 단어에서 나온 카드들을 묶는다.
    var groupID: UUID?

    // SM-2
    var ease: Double
    var intervalDays: Int
    var repetitions: Int
    var lapses: Int
    var dueAt: Date
    var isSuspended: Bool

    var createdAt: Date
    var lastReviewedAt: Date?

    init(
        kind: CardKind,
        prompt: String,
        answer: String,
        note: String = "",
        example: String = "",
        episodeGUID: String? = nil,
        lineIndex: Int? = nil,
        audioStart: Double? = nil,
        audioEnd: Double? = nil,
        takeFilename: String? = nil,
        groupID: UUID? = nil
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.prompt = prompt
        self.answer = answer
        self.note = note
        self.example = example
        self.episodeGUID = episodeGUID
        self.lineIndex = lineIndex
        self.audioStart = audioStart
        self.audioEnd = audioEnd
        self.takeFilename = takeFilename
        self.groupID = groupID
        self.ease = SRS.startingEase
        self.intervalDays = 0
        self.repetitions = 0
        self.lapses = 0
        self.dueAt = .now
        self.isSuspended = false
        self.createdAt = .now
    }

    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .sentence }
        set { kindRaw = newValue.rawValue }
    }

    var isNew: Bool { repetitions == 0 && lapses == 0 }
    var isDue: Bool { !isSuspended && dueAt <= .now }
    /// 간격이 21일을 넘으면 「성숙 카드」. 진짜로 외워진 양에 가장 가까운 지표다.
    var isMature: Bool { intervalDays >= 21 }

    var takeURL: URL? {
        guard let takeFilename else { return nil }
        let url = FileVault.takeURL(takeFilename)
        return FileVault.exists(url) ? url : nil
    }

    var hasAudioSegment: Bool { audioStart != nil && audioEnd != nil }
}

/// 저장 한 번에 카드 여러 장이 나오는 규칙을 한곳에 모아둔다.
enum CardFactory {
    static func sentenceCard(
        korean: String,
        english: String,
        episode: Episode?,
        line: TranscriptLine?
    ) -> StudyCard {
        StudyCard(
            kind: .sentence,
            prompt: korean.trimmed,
            answer: english.trimmed,
            example: line?.text ?? "",
            episodeGUID: episode?.guid,
            lineIndex: line?.index,
            audioStart: line?.start,
            audioEnd: line?.end,
            takeFilename: line?.latestTake?.filename
        )
    }

    static func wordCards(
        word: String,
        meaning: String,
        note: String,
        episode: Episode?,
        line: TranscriptLine?,
        includeProduction: Bool,
        includeListening: Bool
    ) -> [StudyCard] {
        let group = UUID()
        let word = word.trimmed
        let meaning = meaning.trimmed
        let example = line?.text ?? ""
        let segment = wordSegment(for: word, in: line)

        func make(_ kind: CardKind, prompt: String, answer: String) -> StudyCard {
            StudyCard(
                kind: kind,
                prompt: prompt,
                answer: answer,
                note: note.trimmed,
                example: example,
                episodeGUID: episode?.guid,
                lineIndex: line?.index,
                audioStart: segment?.start,
                audioEnd: segment?.end,
                takeFilename: line?.latestTake?.filename,
                groupID: group
            )
        }

        var cards = [make(.wordRecognition, prompt: word, answer: meaning)]
        if includeProduction {
            cards.append(make(.wordProduction, prompt: meaning, answer: word))
        }
        if includeListening {
            cards.append(make(.wordListening, prompt: "", answer: word))
        }
        return cards
    }

    /// 단어가 문장 어디쯤에 있는지로 발음 구간을 어림한다. 합성음 대신 진짜 발화를 쓰기 위한 근사치다.
    static func wordSegment(for word: String, in line: TranscriptLine?) -> (start: Double, end: Double)? {
        guard let line, line.duration > 0 else { return nil }
        let haystack = line.text.lowercased()
        let needle = word.lowercased()
        guard let range = haystack.range(of: needle) else {
            return (line.start, line.end)
        }
        let offset = Double(haystack.distance(from: haystack.startIndex, to: range.lowerBound))
        let width = Double(needle.count)
        let total = Double(max(haystack.count, 1))

        let start = line.start + line.duration * (offset / total)
        let end = start + max(0.8, line.duration * (width / total)) + 0.4
        return (max(line.start, start - 0.25), min(line.end, end))
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}
