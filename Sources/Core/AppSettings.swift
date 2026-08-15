import Foundation
import Observation

/// 설정 화면이 쓰는 값들. 서비스 쪽에서도 같은 객체를 읽는다.
///
/// `@Observable`은 `didSet`이 붙은 프로퍼티를 추적 대상에서 빼므로, 저장은 관찰자 대신
/// `persist()`를 명시적으로 불러 처리한다. 호출 지점은 설정 화면을 닫을 때와 앱이 백그라운드로 갈 때.
@Observable
final class AppSettings {
    var listenMinutes = 20
    var shadowMinutes = 15
    var outputMinutes = 25

    var episodeNotifyEnabled = true
    var episodeNotifyMinute = 7 * 60 + 30
    var reviewNotifyEnabled = true
    var reviewNotifyMinute = 21 * 60
    var streakNotifyEnabled = true

    var onDeviceTranscription = true
    var manualCorrection = false

    var wifiOnlyDownload = true
    var audioRetentionDays = 30

    var makeProductionCards = true
    var makeListeningCards = false
    var dailyNewLimit = 20
    var dailyReviewLimit = 200

    @ObservationIgnored private let store: UserDefaults

    private enum Key {
        static let listenMinutes = "routine.listenMinutes"
        static let shadowMinutes = "routine.shadowMinutes"
        static let outputMinutes = "routine.outputMinutes"

        static let episodeNotifyEnabled = "notify.episode.enabled"
        static let episodeNotifyMinute = "notify.episode.minute"
        static let reviewNotifyEnabled = "notify.review.enabled"
        static let reviewNotifyMinute = "notify.review.minute"
        static let streakNotifyEnabled = "notify.streak.enabled"

        static let onDeviceTranscription = "transcript.onDevice"
        static let manualCorrection = "transcript.manualCorrection"

        static let wifiOnlyDownload = "download.wifiOnly"
        static let audioRetentionDays = "download.retentionDays"

        static let makeProductionCards = "cards.makeProduction"
        static let makeListeningCards = "cards.makeListening"
        static let dailyNewLimit = "cards.dailyNewLimit"
        static let dailyReviewLimit = "cards.dailyReviewLimit"

        static let snoozeDay = "notify.snooze.day"
        static let snoozeCount = "notify.snooze.count"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        load()
    }

    private func load() {
        func int(_ key: String, _ fallback: Int) -> Int {
            store.object(forKey: key) as? Int ?? fallback
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) as? Bool ?? fallback
        }

        listenMinutes = int(Key.listenMinutes, 20)
        shadowMinutes = int(Key.shadowMinutes, 15)
        outputMinutes = int(Key.outputMinutes, 25)

        episodeNotifyEnabled = bool(Key.episodeNotifyEnabled, true)
        episodeNotifyMinute = int(Key.episodeNotifyMinute, 7 * 60 + 30)
        reviewNotifyEnabled = bool(Key.reviewNotifyEnabled, true)
        reviewNotifyMinute = int(Key.reviewNotifyMinute, 21 * 60)
        streakNotifyEnabled = bool(Key.streakNotifyEnabled, true)

        onDeviceTranscription = bool(Key.onDeviceTranscription, true)
        manualCorrection = bool(Key.manualCorrection, false)

        wifiOnlyDownload = bool(Key.wifiOnlyDownload, true)
        audioRetentionDays = int(Key.audioRetentionDays, 30)

        makeProductionCards = bool(Key.makeProductionCards, true)
        makeListeningCards = bool(Key.makeListeningCards, false)
        dailyNewLimit = int(Key.dailyNewLimit, 20)
        dailyReviewLimit = int(Key.dailyReviewLimit, 200)
    }

    func persist() {
        store.set(listenMinutes, forKey: Key.listenMinutes)
        store.set(shadowMinutes, forKey: Key.shadowMinutes)
        store.set(outputMinutes, forKey: Key.outputMinutes)

        store.set(episodeNotifyEnabled, forKey: Key.episodeNotifyEnabled)
        store.set(episodeNotifyMinute, forKey: Key.episodeNotifyMinute)
        store.set(reviewNotifyEnabled, forKey: Key.reviewNotifyEnabled)
        store.set(reviewNotifyMinute, forKey: Key.reviewNotifyMinute)
        store.set(streakNotifyEnabled, forKey: Key.streakNotifyEnabled)

        store.set(onDeviceTranscription, forKey: Key.onDeviceTranscription)
        store.set(manualCorrection, forKey: Key.manualCorrection)

        store.set(wifiOnlyDownload, forKey: Key.wifiOnlyDownload)
        store.set(audioRetentionDays, forKey: Key.audioRetentionDays)

        store.set(makeProductionCards, forKey: Key.makeProductionCards)
        store.set(makeListeningCards, forKey: Key.makeListeningCards)
        store.set(dailyNewLimit, forKey: Key.dailyNewLimit)
        store.set(dailyReviewLimit, forKey: Key.dailyReviewLimit)
    }

    func minutes(for stage: Stage) -> Int {
        switch stage {
        case .listen: listenMinutes
        case .shadow: shadowMinutes
        case .output: outputMinutes
        }
    }

    /// 알림에서 미루기는 하루 두 번까지. 날짜가 바뀌면 카운터가 리셋된다.
    func consumeSnooze() -> Bool {
        let today = DayKey.today
        if store.string(forKey: Key.snoozeDay) != today {
            store.set(today, forKey: Key.snoozeDay)
            store.set(0, forKey: Key.snoozeCount)
        }
        let used = store.integer(forKey: Key.snoozeCount)
        guard used < 2 else { return false }
        store.set(used + 1, forKey: Key.snoozeCount)
        return true
    }
}
