import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadCenter.self) private var downloads
    @Environment(TranscriptionService.self) private var transcription
    @Environment(PlayerEngine.self) private var player
    @Environment(AppRouter.self) private var router

    @Query(sort: \Episode.publishedAt, order: .reverse) private var episodes: [Episode]
    @Query(sort: \StudyCard.createdAt, order: .reverse) private var cards: [StudyCard]

    @State private var section: LibrarySection = .episodes
    @State private var search = ""
    @State private var isSyncing = false
    @State private var syncMessage: String?
    @State private var showsSettings = false

    private enum LibrarySection: String, CaseIterable, Identifiable {
        case episodes, cards, takes
        var id: String { rawValue }
    }

    private var takes: [ShadowTake] {
        episodes.flatMap { $0.lines }.flatMap(\.takes).sorted { $0.recordedAt > $1.recordedAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 13) {
                Picker("구분", selection: $section) {
                    Text("에피소드").tag(LibrarySection.episodes)
                    Text("카드 \(cards.count)").tag(LibrarySection.cards)
                    Text("녹음 \(takes.count)").tag(LibrarySection.takes)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)

                if let syncMessage {
                    Text(syncMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.dim)
                        .padding(.horizontal, 22)
                }

                List {
                    switch section {
                    case .episodes: episodeRows
                    case .cards: cardRows
                    case .takes: takeRows
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "제목·표현 검색")
                .refreshable { await sync() }
            }
            .padding(.top, 8)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("라이브러리")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await sync() } } label: {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isSyncing)
                }
            }
            .sheet(isPresented: $showsSettings) { SettingsView() }
        }
    }

    // MARK: - 에피소드

    private var filteredEpisodes: [Episode] {
        guard !search.isBlank else { return episodes }
        return episodes.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    @ViewBuilder
    private var episodeRows: some View {
        if filteredEpisodes.isEmpty {
            EmptyHint(
                icon: "tray",
                title: "에피소드가 없습니다",
                message: "위 새로고침을 눌러 BBC 피드를 확인해 보세요."
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(filteredEpisodes) { episode in
                episodeRow(episode)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Palette.lineSoft)
                    .swipeActions(edge: .trailing) {
                        Button("오늘로") { assign(episode) }.tint(Palette.shadow)
                    }
            }
        }
    }

    private func episodeRow(_ episode: Episode) -> some View {
        HStack(spacing: 12) {
            // 상태는 아이콘 여러 개 대신 세로 막대 하나로 읽힌다.
            StatusBar(color: statusColor(episode))

            VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(episode.hasAudio ? Palette.text : Palette.dim)
                    .lineLimit(1)
                Text(statusText(episode)).microLabel()
            }

            Spacer(minLength: 6)

            trailingControl(episode)
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ episode: Episode) -> Color {
        if episode.isCompleted || episode.hasTranscript { return Palette.good }
        if transcription.isRunning(episode.guid) || downloads.isDownloading(episode.guid) { return Palette.listen }
        if episode.hasAudio { return Palette.shadow }
        return Palette.line
    }

    private func statusText(_ episode: Episode) -> String {
        let date = episode.publishedAt.formatted(.dateTime.month().day().locale(Locale(identifier: "ko_KR")))
        var parts = [date]
        if episode.durationSeconds > 0 { parts.append(episode.durationSeconds.clockLabel) }

        if episode.assignedDayKey == DayKey.today {
            parts.append("오늘 진행 중")
        } else if episode.isCompleted {
            parts.append("완료")
        } else if let value = transcription.progress[episode.guid] {
            parts.append("스크립트 생성 중 \(Int(value * 100))%")
        } else if episode.hasTranscript {
            parts.append("스크립트 \(episode.lines.count)문장")
        } else if episode.hasAudio {
            parts.append("스크립트 없음")
        } else {
            parts.append("오디오 없음")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func trailingControl(_ episode: Episode) -> some View {
        if let value = downloads.progressValue(for: episode.guid) {
            Text("\(Int(value * 100))%")
                .font(.mono(11))
                .foregroundStyle(Palette.listen)
        } else if !episode.hasAudio {
            Button {
                Task { await downloads.download(episode, allowsCellular: !settings.wifiOnlyDownload) }
            } label: {
                Image(systemName: "arrow.down.circle").foregroundStyle(Palette.dim)
            }
            .buttonStyle(.plain)
        } else if !episode.hasTranscript, !transcription.isRunning(episode.guid) {
            Button {
                Task {
                    await transcription.transcribe(
                        episode: episode,
                        preferOnDevice: settings.onDeviceTranscription,
                        context: context
                    )
                }
            } label: {
                Image(systemName: "waveform.badge.plus").foregroundStyle(Palette.dim)
            }
            .buttonStyle(.plain)
        } else if episode.isCompleted {
            Image(systemName: "checkmark").foregroundStyle(Palette.good).font(.system(size: 12, weight: .bold))
        }
    }

    // MARK: - 카드

    private var filteredCards: [StudyCard] {
        guard !search.isBlank else { return cards }
        return cards.filter {
            $0.prompt.localizedCaseInsensitiveContains(search) || $0.answer.localizedCaseInsensitiveContains(search)
        }
    }

    @ViewBuilder
    private var cardRows: some View {
        if filteredCards.isEmpty {
            EmptyHint(
                icon: "rectangle.on.rectangle",
                title: "저장한 카드가 없습니다",
                message: "출력 단계에서 막힌 표현을 저장하면 여기에 쌓입니다."
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(filteredCards) { card in
                HStack(spacing: 12) {
                    StatusBar(color: card.isSuspended ? Palette.line : (card.isMature ? Palette.good : Palette.shadow), height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.kind.isAudioPrompt ? card.answer : card.prompt)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text("\(card.kind.directionLabel) · \(dueLabel(card))").microLabel()
                    }

                    Spacer(minLength: 6)
                    Chip(text: card.kind.label)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Palette.lineSoft)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        context.delete(card)
                        try? context.save()
                    } label: { Text("삭제") }

                    Button(card.isSuspended ? "재개" : "정지") {
                        card.isSuspended.toggle()
                        try? context.save()
                    }
                    .tint(Palette.dim)
                }
            }
        }
    }

    private func dueLabel(_ card: StudyCard) -> String {
        if card.isSuspended { return "정지됨" }
        if card.isDue { return "오늘 복습" }
        let days = DayKey.days(from: DayKey.today, to: DayKey.key(card.dueAt))
        return days <= 0 ? "오늘 복습" : "\(days)일 후"
    }

    // MARK: - 녹음

    @ViewBuilder
    private var takeRows: some View {
        if takes.isEmpty {
            EmptyHint(
                icon: "mic",
                title: "녹음이 없습니다",
                message: "섀도잉 단계에서 녹음하면 문장에 붙어 남고, 여기서 언제든 다시 들을 수 있습니다."
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            ForEach(takes) { take in
                HStack(spacing: 12) {
                    StatusBar(color: Palette.output, height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(take.line?.text ?? "문장 없음")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Text("\(take.recordedAt.formatted(.dateTime.month().day().hour().minute())) · \(take.duration.clockLabel)")
                            .microLabel()
                    }

                    Spacer(minLength: 6)

                    Button {
                        guard let url = take.url else { return }
                        try? player.load(url: url, owner: take.filename)
                        player.clearSegment()
                        player.seek(to: 0)
                        player.play()
                    } label: {
                        Image(systemName: "play.circle").foregroundStyle(Palette.output)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(Palette.lineSoft)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        FileVault.remove(FileVault.takeURL(take.filename))
                        context.delete(take)
                        try? context.save()
                    } label: { Text("삭제") }
                }
            }
        }
    }

    // MARK: - 동작

    private func assign(_ episode: Episode) {
        StudyPlanner.assign(episode, context: context)
        try? context.save()
        router.selectedTab = .today
    }

    private func sync() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let added = try await FeedSync.sync(context: context)
            try? context.save()
            syncMessage = added == 0 ? "새 에피소드가 없습니다." : "새 에피소드 \(added)편을 받았습니다."
        } catch {
            syncMessage = (error as? LocalizedError)?.errorDescription ?? "피드를 확인하지 못했습니다."
        }
    }
}
