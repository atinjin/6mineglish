import Foundation
import SwiftData

/// 오늘 뭘 할지 정하고 기록을 붙이는 곳. 「에피소드 선택」이라는 결정을 앱이 대신 내린다.
@MainActor
enum StudyPlanner {
    static func allEpisodes(_ context: ModelContext) -> [Episode] {
        let descriptor = FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func allCards(_ context: ModelContext) -> [StudyCard] {
        let descriptor = FetchDescriptor<StudyCard>(sortBy: [SortDescriptor(\.dueAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func allLogs(_ context: ModelContext) -> [RoutineLog] {
        let descriptor = FetchDescriptor<RoutineLog>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 이미 배정돼 있으면 그것, 없으면 아직 안 한 최신 편을 오늘 자리에 올린다.
    @discardableResult
    static func todaysEpisode(_ context: ModelContext, dayKey: String = DayKey.today) -> Episode? {
        let episodes = allEpisodes(context)

        if let assigned = episodes.first(where: { $0.assignedDayKey == dayKey }) {
            return assigned
        }

        guard let next = episodes.first(where: { $0.assignedDayKey == nil && !$0.isCompleted }) else {
            return nil
        }
        next.assignedDayKey = dayKey
        log(for: dayKey, context: context).episodeGUID = next.guid
        return next
    }

    /// 라이브러리에서 다른 편을 오늘로 끌어온다. 자동 배정은 기본값이지 제약이 아니다.
    static func assign(_ episode: Episode, context: ModelContext, dayKey: String = DayKey.today) {
        for other in allEpisodes(context) where other.assignedDayKey == dayKey && other.guid != episode.guid {
            other.assignedDayKey = nil
        }
        episode.assignedDayKey = dayKey
        log(for: dayKey, context: context).episodeGUID = episode.guid
    }

    @discardableResult
    static func log(for dayKey: String = DayKey.today, context: ModelContext) -> RoutineLog {
        let descriptor = FetchDescriptor<RoutineLog>(predicate: #Predicate { $0.dayKey == dayKey })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = RoutineLog(dayKey: dayKey)
        context.insert(created)
        return created
    }

    /// 3단계를 모두 마친 날만 센다. 절반만 한 날은 기록에는 남지만 연속은 끊긴다.
    static func streak(_ context: ModelContext, today: String = DayKey.today) -> Int {
        let completed = Set(allLogs(context).filter(\.isComplete).map(\.dayKey))
        guard !completed.isEmpty else { return 0 }

        var cursor = completed.contains(today) ? today : DayKey.adding(-1, to: today)
        var count = 0
        while completed.contains(cursor) {
            count += 1
            cursor = DayKey.adding(-1, to: cursor)
        }
        return count
    }

    static func longestStreak(_ context: ModelContext) -> Int {
        let days = allLogs(context).filter(\.isComplete).map(\.dayKey).sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var run = 1
        for index in 1..<days.count {
            if DayKey.days(from: days[index - 1], to: days[index]) == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }
        return longest
    }

    static func markStage(_ stage: Stage, done: Bool, context: ModelContext) {
        let entry = log(context: context)
        entry.setDone(stage, done)

        // 3단계를 다 끝냈으면 오늘 에피소드를 완료 처리한다.
        if entry.isComplete,
           let guid = entry.episodeGUID,
           let episode = allEpisodes(context).first(where: { $0.guid == guid }),
           episode.completedAt == nil {
            episode.completedAt = .now
        }
    }

    static func recordStudyTime(_ seconds: Int, stage: Stage, context: ModelContext) {
        guard seconds > 0 else { return }
        log(context: context).addSeconds(seconds, to: stage)
    }

    static func recordReview(count: Int = 1, context: ModelContext) {
        log(context: context).reviewedCount += count
    }
}

/// 피드에서 받은 항목을 저장소에 합친다. 이미 있는 guid는 건너뛴다.
@MainActor
enum FeedSync {
    @discardableResult
    static func sync(context: ModelContext, service: RSSFeedService = RSSFeedService()) async throws -> Int {
        let items = try await service.fetch()
        let existing = Set(StudyPlanner.allEpisodes(context).map(\.guid))

        var added = 0
        for item in items where !existing.contains(item.guid) {
            let episode = Episode(
                guid: item.guid,
                title: item.title,
                summary: item.summary,
                publishedAt: item.publishedAt,
                audioURLString: item.audioURL.absoluteString,
                pageURLString: item.pageURL?.absoluteString,
                durationSeconds: item.duration
            )
            context.insert(episode)
            added += 1
        }
        return added
    }
}
