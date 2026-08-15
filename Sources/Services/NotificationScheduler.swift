import Foundation
import Observation
import SwiftData
import UserNotifications

/// 알림 설계의 절반은 「보내지 않는 규칙」이다. 할 일이 실제로 남아 있을 때만 예약한다.
@MainActor
enum NotificationScheduler {
    enum ID {
        static let episode = "sixmin.episode"
        static let review = "sixmin.review"
        static let streak = "sixmin.streak"
        static let snoozePrefix = "sixmin.review.snooze."
        static let transcriptPrefix = "sixmin.transcript."
    }

    enum Category {
        static let review = "SIXMIN_REVIEW"
        static let episode = "SIXMIN_EPISODE"
    }

    enum Action {
        static let reviewNow = "SIXMIN_REVIEW_NOW"
        static let snooze = "SIXMIN_SNOOZE"
    }

    static let streakMinuteOfDay = 22 * 60 + 30
    static let snoozeInterval: TimeInterval = 3600

    static func registerCategories() {
        let review = UNNotificationCategory(
            identifier: Category.review,
            actions: [
                UNNotificationAction(identifier: Action.reviewNow, title: "바로 복습", options: [.foreground]),
                UNNotificationAction(identifier: Action.snooze, title: "1시간 뒤", options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
        let episode = UNNotificationCategory(
            identifier: Category.episode,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([review, episode])
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// 데이터가 바뀔 때마다 통째로 다시 계산한다. 조건이 사라진 알림은 예약이 지워진다.
    static func refresh(context: ModelContext, settings: AppSettings) async {
        let center = UNUserNotificationCenter.current()
        let authorized = await requestAuthorization()
        guard authorized else {
            center.removePendingNotificationRequests(withIdentifiers: [ID.episode, ID.review, ID.streak])
            return
        }

        let today = DayKey.today
        let log = StudyPlanner.log(for: today, context: context)
        let episode = StudyPlanner.allEpisodes(context).first { $0.assignedDayKey == today }
        let dueCount = CardQueue.counts(from: StudyPlanner.allCards(context))

        scheduleEpisode(episode: episode, log: log, settings: settings, center: center)
        scheduleReview(counts: dueCount, settings: settings, center: center)
        scheduleStreak(context: context, log: log, settings: settings, center: center)
    }

    // MARK: - 개별 알림

    private static func scheduleEpisode(
        episode: Episode?,
        log: RoutineLog,
        settings: AppSettings,
        center: UNUserNotificationCenter
    ) {
        // 이미 들었으면 보내지 않는다.
        guard settings.episodeNotifyEnabled, let episode, episode.hasAudio, !log.listenDone else {
            center.removePendingNotificationRequests(withIdentifiers: [ID.episode])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "오늘의 에피소드가 준비됐어요"
        var detail = episode.title
        if episode.durationSeconds > 0 {
            detail += " · \(episode.durationSeconds.clockLabel)"
        }
        if episode.hasTranscript {
            detail += " · 스크립트 \(episode.lines.count)문장"
        }
        content.body = detail
        content.sound = .default
        content.categoryIdentifier = Category.episode

        schedule(id: ID.episode, content: content, atMinuteOfDay: settings.episodeNotifyMinute, center: center)
    }

    private static func scheduleReview(
        counts: CardQueue.Counts,
        settings: AppSettings,
        center: UNUserNotificationCenter
    ) {
        // 오늘 복습 큐를 비웠으면 아무것도 오지 않는다.
        guard settings.reviewNotifyEnabled, counts.total > 0 else {
            center.removePendingNotificationRequests(withIdentifiers: [ID.review])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "복습할 시간이에요"
        content.body = bodyText(for: counts)
        content.sound = .default
        content.categoryIdentifier = Category.review
        content.badge = NSNumber(value: counts.total)

        schedule(id: ID.review, content: content, atMinuteOfDay: settings.reviewNotifyMinute, center: center)
    }

    private static func scheduleStreak(
        context: ModelContext,
        log: RoutineLog,
        settings: AppSettings,
        center: UNUserNotificationCenter
    ) {
        let streak = StudyPlanner.streak(context)
        // 연속이 2일 이하면 이 알림 자체가 없다.
        guard settings.streakNotifyEnabled, streak >= 3, !log.isComplete else {
            center.removePendingNotificationRequests(withIdentifiers: [ID.streak])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(streak)일 연속이 오늘 끊깁니다"
        let remaining = Stage.allCases.filter { !log.isDone($0) }.map(\.title).joined(separator: " · ")
        content.body = remaining.isEmpty ? "루틴을 마무리해 주세요" : "남은 단계 — \(remaining)"
        content.sound = .default

        schedule(id: ID.streak, content: content, atMinuteOfDay: streakMinuteOfDay, center: center)
    }

    /// 백그라운드에서 스크립트가 만들어졌을 때만. 소리 없이 목록에만 쌓인다.
    static func notifyTranscriptReady(episodeTitle: String, lineCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "스크립트가 준비됐어요"
        content.body = "\(episodeTitle) · \(lineCount)문장"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: ID.transcriptPrefix + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 알림에서 바로 미루기. 앱을 열지 않고 처리되고 하루 두 번까지만 허용한다.
    static func snoozeReview(settings: AppSettings, counts: CardQueue.Counts) {
        guard counts.total > 0, settings.consumeSnooze() else { return }

        let content = UNMutableNotificationContent()
        content.title = "복습할 시간이에요"
        content.body = bodyText(for: counts)
        content.sound = .default
        content.categoryIdentifier = Category.review

        let request = UNNotificationRequest(
            identifier: ID.snoozePrefix + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: snoozeInterval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Helpers

    /// "복습할 시간입니다"보다 "단어 6장 · 문장 8장"이 열게 만든다.
    static func bodyText(for counts: CardQueue.Counts) -> String {
        var parts: [String] = []
        if counts.new > 0 { parts.append("신규 \(counts.new)장") }
        if counts.review > 0 { parts.append("복습 \(counts.review)장") }
        if counts.relearning > 0 { parts.append("다시 \(counts.relearning)장") }
        return parts.isEmpty ? "\(counts.total)장이 기다립니다" : parts.joined(separator: " · ") + "이 기다립니다"
    }

    private static func schedule(
        id: String,
        content: UNMutableNotificationContent,
        atMinuteOfDay minute: Int,
        center: UNUserNotificationCenter
    ) {
        center.removePendingNotificationRequests(withIdentifiers: [id])

        var components = DateComponents()
        components.hour = minute / 60
        components.minute = minute % 60

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        center.add(request)
    }
}

/// 알림 탭·액션을 앱 안 동작으로 옮긴다.
@MainActor
@Observable
final class AppRouter {
    var selectedTab: RootTab = .today
    var pendingReviewJump = false

    func openReview() {
        selectedTab = .review
        pendingReviewJump = true
    }
}

/// 알림 액션을 앱 동작으로 옮긴다. 실제 처리는 앱이 시작할 때 꽂아 넣는 두 클로저가 담당한다.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    @MainActor static var onReviewNow: (() -> Void)?
    @MainActor static var onSnooze: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier

        await MainActor.run {
            switch action {
            case NotificationScheduler.Action.snooze:
                Self.onSnooze?()

            case NotificationScheduler.Action.reviewNow, UNNotificationDefaultActionIdentifier:
                guard category == NotificationScheduler.Category.review else { return }
                Self.onReviewNow?()

            default:
                break
            }
        }
    }
}
