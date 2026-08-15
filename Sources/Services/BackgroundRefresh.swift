import BackgroundTasks
import Foundation
import SwiftData

/// 하루 한 번쯤 피드를 확인하고 오늘 에피소드를 미리 받아둔다. 알림 예약도 여기서 갱신한다.
enum BackgroundRefresh {
    static let taskID = "com.sixmin.app.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// 백그라운드에서는 화면이 쓰던 객체를 넘겨받지 않고 필요한 것만 새로 만든다.
    /// `AppSettings`는 UserDefaults를 읽으므로 새 인스턴스도 같은 값을 본다.
    @MainActor
    static func run(container: ModelContainer) async {
        defer { schedule() }

        let context = container.mainContext
        let settings = AppSettings()
        let downloads = DownloadCenter()

        _ = try? await FeedSync.sync(context: context)

        if let episode = StudyPlanner.todaysEpisode(context), !episode.hasAudio {
            await downloads.download(episode, allowsCellular: !settings.wifiOnlyDownload)
        }

        try? context.save()
        await NotificationScheduler.refresh(context: context, settings: settings)
    }
}
