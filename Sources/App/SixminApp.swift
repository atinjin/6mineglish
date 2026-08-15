import SwiftData
import SwiftUI
import UserNotifications

@main
struct SixminApp: App {
    @State private var settings: AppSettings
    @State private var clock: RoutineClock
    @State private var player = PlayerEngine()
    @State private var recorder = RecorderEngine()
    @State private var downloads = DownloadCenter()
    @State private var transcription = TranscriptionService()
    @State private var waveforms = WaveformStore()
    @State private var router = AppRouter()
    @State private var notificationDelegate = NotificationDelegate()

    @Environment(\.scenePhase) private var scenePhase

    private let container: ModelContainer

    init() {
        FileVault.prepare()

        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _clock = State(initialValue: RoutineClock(settings: settings))

        let schema = Schema([
            Episode.self,
            TranscriptLine.self,
            ShadowTake.self,
            StudyCard.self,
            RoutineLog.self,
        ])
        do {
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
            )
        } catch {
            fatalError("저장소를 열지 못했습니다: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(clock)
                .environment(player)
                .environment(recorder)
                .environment(downloads)
                .environment(transcription)
                .environment(waveforms)
                .environment(router)
                .tint(Palette.shadow)
                .preferredColorScheme(.dark)
                .task { await bootstrap() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                clock.pauseAll()
                settings.persist()
                BackgroundRefresh.schedule()
                Task { await NotificationScheduler.refresh(context: container.mainContext, settings: settings) }
            case .active:
                NotificationScheduler.clearBadge()
                clock.syncDurations(with: settings)
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskID)) {
            await BackgroundRefresh.run(container: container)
        }
    }

    @MainActor
    private func bootstrap() async {
        NotificationScheduler.registerCategories()

        NotificationDelegate.onReviewNow = { [router] in
            router.openReview()
        }
        NotificationDelegate.onSnooze = { [settings, container] in
            let counts = CardQueue.counts(from: StudyPlanner.allCards(container.mainContext))
            NotificationScheduler.snoozeReview(settings: settings, counts: counts)
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate

        let context = container.mainContext

        // 첫 실행이면 피드를 받아 오늘 자리를 채운다.
        if StudyPlanner.allEpisodes(context).isEmpty {
            _ = try? await FeedSync.sync(context: context)
        }
        StudyPlanner.todaysEpisode(context)
        try? context.save()

        _ = await NotificationScheduler.requestAuthorization()
        await NotificationScheduler.refresh(context: context, settings: settings)
        BackgroundRefresh.schedule()
    }
}
