import Foundation

enum Grade: Int, CaseIterable, Identifiable {
    case again, hard, good, easy

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: "다시"
        case .hard: "어려움"
        case .good: "좋음"
        case .easy: "쉬움"
        }
    }
}

/// Anki의 SM-2. 카드 종류가 달라도 계산식은 하나다.
enum SRS {
    static let startingEase: Double = 2.5
    static let minimumEase: Double = 1.3
    static let maximumEase: Double = 3.0
    /// 「다시」는 날짜를 넘기지 않고 같은 세션 안에서 다시 만난다.
    static let againDelay: TimeInterval = 600

    struct Outcome {
        var ease: Double
        var intervalDays: Int
        var repetitions: Int
        var dueAt: Date
        var isLapse: Bool
    }

    static func next(
        ease: Double,
        intervalDays: Int,
        repetitions: Int,
        grade: Grade,
        now: Date = .now
    ) -> Outcome {
        switch grade {
        case .again:
            return Outcome(
                ease: clampEase(ease - 0.20),
                intervalDays: 0,
                repetitions: 0,
                dueAt: now.addingTimeInterval(againDelay),
                isLapse: true
            )

        case .hard:
            let interval: Int
            switch repetitions {
            case 0: interval = 1
            case 1: interval = 3
            default: interval = max(intervalDays + 1, Int((Double(intervalDays) * 1.2).rounded()))
            }
            return dayOutcome(ease: clampEase(ease - 0.15), interval: interval, repetitions: repetitions + 1, now: now)

        case .good:
            let interval: Int
            switch repetitions {
            case 0: interval = 1
            case 1: interval = 6
            default: interval = max(intervalDays + 1, Int((Double(intervalDays) * ease).rounded()))
            }
            return dayOutcome(ease: clampEase(ease), interval: interval, repetitions: repetitions + 1, now: now)

        case .easy:
            let interval: Int
            switch repetitions {
            case 0: interval = 4
            case 1: interval = 8
            default: interval = max(intervalDays + 2, Int((Double(intervalDays) * ease * 1.3).rounded()))
            }
            return dayOutcome(ease: clampEase(ease + 0.15), interval: interval, repetitions: repetitions + 1, now: now)
        }
    }

    static func apply(_ grade: Grade, to card: StudyCard, now: Date = .now) {
        let outcome = next(
            ease: card.ease,
            intervalDays: card.intervalDays,
            repetitions: card.repetitions,
            grade: grade,
            now: now
        )
        card.ease = outcome.ease
        card.intervalDays = outcome.intervalDays
        card.repetitions = outcome.repetitions
        card.dueAt = outcome.dueAt
        card.lastReviewedAt = now
        if outcome.isLapse { card.lapses += 1 }
    }

    /// 버튼을 누르기 전에 결과를 보여주기 위한 미리보기. 카드는 건드리지 않는다.
    static func previewLabel(_ grade: Grade, for card: StudyCard, now: Date = .now) -> String {
        let outcome = next(
            ease: card.ease,
            intervalDays: card.intervalDays,
            repetitions: card.repetitions,
            grade: grade,
            now: now
        )
        if outcome.intervalDays == 0 {
            return "\(Int(againDelay / 60))분"
        }
        if outcome.intervalDays >= 30 {
            let months = Double(outcome.intervalDays) / 30.0
            return String(format: "%.1f개월", months)
        }
        return "\(outcome.intervalDays)일"
    }

    private static func dayOutcome(ease: Double, interval: Int, repetitions: Int, now: Date) -> Outcome {
        let bounded = max(1, interval)
        let base = Calendar.current.startOfDay(for: now)
        let due = Calendar.current.date(byAdding: .day, value: bounded, to: base)
            ?? now.addingTimeInterval(Double(bounded) * 86_400)
        return Outcome(ease: ease, intervalDays: bounded, repetitions: repetitions, dueAt: due, isLapse: false)
    }

    private static func clampEase(_ value: Double) -> Double {
        min(maximumEase, max(minimumEase, value))
    }
}

/// 오늘 복습할 카드를 고르는 규칙. 신규 상한이 여기서 걸린다.
enum CardQueue {
    struct Counts {
        var new = 0
        var review = 0
        var relearning = 0
        var total: Int { new + review + relearning }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, word, sentence
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "전체"
            case .word: "단어"
            case .sentence: "문장"
            }
        }

        func matches(_ card: StudyCard) -> Bool {
            switch self {
            case .all: true
            case .word: card.kind.isWord
            case .sentence: card.kind == .sentence
            }
        }
    }

    static func due(from cards: [StudyCard], now: Date = .now) -> [StudyCard] {
        cards.filter { !$0.isSuspended && $0.dueAt <= now }
    }

    static func counts(from cards: [StudyCard], filter: Filter = .all, now: Date = .now) -> Counts {
        var counts = Counts()
        for card in due(from: cards, now: now) where filter.matches(card) {
            if card.isNew {
                counts.new += 1
            } else if card.intervalDays == 0 {
                counts.relearning += 1
            } else {
                counts.review += 1
            }
        }
        return counts
    }

    /// 신규는 뒤로 섞어 넣는다. 앞머리가 전부 처음 보는 카드면 세션이 무거워진다.
    static func build(
        from cards: [StudyCard],
        filter: Filter,
        newLimit: Int,
        reviewLimit: Int,
        now: Date = .now
    ) -> [StudyCard] {
        let pool = due(from: cards, now: now).filter { filter.matches($0) }

        let newCards = pool.filter(\.isNew)
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(max(0, newLimit))

        let others = pool.filter { !$0.isNew }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(max(0, reviewLimit))

        var queue = Array(others)
        guard !newCards.isEmpty else { return queue }

        // 신규를 일정 간격으로 끼워 넣어 난이도를 고르게 편다.
        let stride = max(1, queue.count / (newCards.count + 1))
        for (offset, card) in newCards.enumerated() {
            let index = min(queue.count, (offset + 1) * stride + offset)
            queue.insert(card, at: index)
        }
        return queue
    }

    /// 짝 맞추기 대상: 오늘 만기이거나 최근 7일 안에 저장한 단어. 아무거나 8개를 뽑으면 복습이 안 된다.
    static func pairCandidates(from cards: [StudyCard], limit: Int = 8, now: Date = .now) -> [StudyCard] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let pool = cards.filter { card in
            card.kind == .wordRecognition
                && !card.isSuspended
                && !card.prompt.isBlank
                && !card.answer.isBlank
                && (card.dueAt <= now || card.createdAt >= weekAgo)
        }
        return Array(pool.shuffled().prefix(limit))
    }
}
