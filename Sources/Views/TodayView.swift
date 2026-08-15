import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadCenter.self) private var downloads
    @Environment(TranscriptionService.self) private var transcription
    @Environment(WaveformStore.self) private var waveforms
    @Environment(AppRouter.self) private var router

    @Query(sort: \Episode.publishedAt, order: .reverse) private var episodes: [Episode]
    @Query private var cards: [StudyCard]
    @Query private var logs: [RoutineLog]

    @State private var episode: Episode?

    private var today: String { DayKey.today }
    private var log: RoutineLog? { logs.first { $0.dayKey == today } }
    private var counts: CardQueue.Counts { CardQueue.counts(from: cards) }
    private var streak: Int { StudyPlanner.streak(context) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    if let episode {
                        episodeCard(episode)
                        ForEach(Stage.allCases) { stage in
                            stageRow(stage, episode: episode)
                        }
                    } else {
                        EmptyHint(
                            icon: "antenna.radiowaves.left.and.right",
                            title: "아직 에피소드가 없습니다",
                            message: "라이브러리에서 새 에피소드를 확인해 보세요."
                        )
                    }

                    reviewCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("오늘")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if streak > 0 {
                        Chip(text: "\(streak)일 연속", color: Palette.output, isActive: true)
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text(dateLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .background(Palette.surface)
            }
        }
        .task { refreshAssignment() }
        .onChange(of: episodes.count) { _, _ in refreshAssignment() }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: .now)
    }

    // MARK: - 에피소드 카드

    private func episodeCard(_ episode: Episode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(episode.shortCode).microLabel()
                Spacer()
                Text("6 Minute English").microLabel()
            }

            Text(episode.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            WaveformView(
                samples: waveforms.placeholder(key: episode.guid),
                progress: 0,
                color: Palette.listen
            )
            .frame(height: 44)

            HStack(spacing: 7) {
                if episode.durationSeconds > 0 {
                    Chip(text: episode.durationSeconds.clockLabel)
                }
                audioChip(episode)
                transcriptChip(episode)
            }
        }
        .cardSurface()
        .task(id: episode.guid) { await prepare(episode) }
    }

    @ViewBuilder
    private func audioChip(_ episode: Episode) -> some View {
        if let value = downloads.progressValue(for: episode.guid) {
            Chip(text: "\(Int(value * 100))%", color: Palette.listen, isActive: true)
        } else if episode.hasAudio {
            Chip(text: "오디오 준비됨", color: Palette.good, isActive: true)
        } else {
            Button {
                Task { await downloads.download(episode, allowsCellular: !settings.wifiOnlyDownload) }
            } label: {
                Chip(text: "오디오 받기", color: Palette.dim, icon: "arrow.down")
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func transcriptChip(_ episode: Episode) -> some View {
        if let value = transcription.progress[episode.guid] {
            Chip(text: "스크립트 \(Int(value * 100))%", color: Palette.listen, isActive: true)
        } else if episode.hasTranscript {
            Chip(text: "스크립트 \(episode.lines.count)문장", color: Palette.good, isActive: true)
        } else if episode.hasAudio {
            Button {
                Task {
                    await transcription.transcribe(
                        episode: episode,
                        preferOnDevice: settings.onDeviceTranscription,
                        context: context
                    )
                }
            } label: {
                Chip(text: "스크립트 만들기", color: Palette.dim, icon: "waveform")
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 단계 행

    private func stageRow(_ stage: Stage, episode: Episode) -> some View {
        let isDone = log?.isDone(stage) ?? false
        let isCurrent = !isDone && Stage.allCases.first { !(log?.isDone($0) ?? false) } == stage

        return NavigationLink {
            destination(for: stage, episode: episode)
        } label: {
            HStack(spacing: 13) {
                Text(stage.number)
                    .font(.mono(12, .bold))
                    .foregroundStyle(isDone || isCurrent ? stage.color : Palette.faint)
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(stage.title)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(isCurrent || isDone ? Palette.text : Palette.dim)
                    Text("\(stage.latinTitle) · \(settings.minutes(for: stage))분").microLabel()
                }

                Spacer(minLength: 8)

                Text(statusText(stage, episode: episode, isDone: isDone))
                    .font(.system(size: 12.5))
                    .foregroundStyle(isDone ? Palette.good : (isCurrent ? stage.color : Palette.faint))
                    .multilineTextAlignment(.trailing)

                Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: isDone ? 20 : 13, weight: .semibold))
                    .foregroundStyle(isDone ? Palette.good : Palette.faint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isCurrent ? stage.color.opacity(0.07) : Palette.raised,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isCurrent ? stage.color : Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ stage: Stage, episode: Episode, isDone: Bool) -> String {
        if isDone { return "완료" }
        switch stage {
        case .shadow where episode.hasTranscript:
            let recorded = episode.lines.filter(\.hasTake).count
            return "\(recorded) / \(episode.lines.count)"
        default:
            return Stage.allCases.first { !(log?.isDone($0) ?? false) } == stage ? "진행" : "대기"
        }
    }

    @ViewBuilder
    private func destination(for stage: Stage, episode: Episode) -> some View {
        switch stage {
        case .listen: ListenView(episode: episode)
        case .shadow: ShadowView(episode: episode)
        case .output: OutputView(episode: episode)
        }
    }

    // MARK: - 복습 카드

    private var reviewCard: some View {
        Button {
            router.selectedTab = .review
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("오늘 복습")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(counts.total == 0 ? "다 끝냈습니다" : "\(counts.total)장 · 신규 \(counts.new)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.dim)
                }
                Spacer()
                Chip(
                    text: counts.total == 0 ? "완료" : "시작",
                    color: counts.total == 0 ? Palette.good : Palette.shadow,
                    isActive: true
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 준비

    private func refreshAssignment() {
        episode = StudyPlanner.todaysEpisode(context)
        try? context.save()
    }

    /// 오디오가 없으면 받고, 받았으면 파형을 뽑는다. 스크립트 생성은 사용자가 누를 때만.
    private func prepare(_ episode: Episode) async {
        if !episode.hasAudio, downloads.progressValue(for: episode.guid) == nil {
            await downloads.download(episode, allowsCellular: !settings.wifiOnlyDownload)
        }
        if let url = episode.localAudioURL {
            waveforms.load(url: url, key: episode.guid)
        }
        try? context.save()
    }
}
