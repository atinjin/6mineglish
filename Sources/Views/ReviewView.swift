import SwiftData
import SwiftUI

/// 복습 탭. 카드와 짝 맞추기 두 방식이 여기서 갈라진다.
struct ReviewHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    @Query private var cards: [StudyCard]

    @State private var mode: Mode = .cards
    @State private var filter: CardQueue.Filter = .all

    private enum Mode: String, CaseIterable, Identifiable {
        case cards, pairs
        var id: String { rawValue }
        var title: String { self == .cards ? "카드" : "짝 맞추기" }
    }

    private var counts: CardQueue.Counts { CardQueue.counts(from: cards, filter: filter) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 13) {
                Picker("방식", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)

                switch mode {
                case .cards:
                    CardSessionView(filter: $filter)
                case .pairs:
                    PairMatchView()
                }
            }
            .padding(.top, 8)
            .background(Palette.surface.ignoresSafeArea())
            .navigationTitle("복습")
        }
        .onAppear {
            guard router.pendingReviewJump else { return }
            router.pendingReviewJump = false
            mode = .cards
        }
        .onChange(of: counts.total) { _, _ in
            Task { await NotificationScheduler.refresh(context: context, settings: settings) }
        }
    }
}

/// 플래시카드 세션. 문장 카드와 단어 카드가 같은 평가 버튼을 쓰되 뒷면 구성만 다르다.
struct CardSessionView: View {
    @Binding var filter: CardQueue.Filter

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerEngine.self) private var player

    @Query private var cards: [StudyCard]
    @Query(sort: \Episode.publishedAt, order: .reverse) private var episodes: [Episode]

    @State private var queue: [StudyCard] = []
    @State private var index = 0
    @State private var isRevealed = false

    private var current: StudyCard? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    private var counts: CardQueue.Counts { CardQueue.counts(from: cards, filter: filter) }

    var body: some View {
        VStack(spacing: 13) {
            filterBar

            if let card = current {
                StageProgressRail(stage: .shadow, progress: Double(index) / Double(max(queue.count, 1)))
                    .padding(.horizontal, 22)

                cardFace(card)
                gradeButtons(card)
            } else {
                Spacer()
                EmptyHint(
                    icon: counts.total == 0 ? "checkmark.circle" : "play.circle",
                    title: counts.total == 0 ? "오늘 복습을 다 끝냈습니다" : "복습할 카드가 준비됐습니다",
                    message: counts.total == 0
                        ? "다음 만기가 되면 알림으로 알려드릴게요."
                        : "\(counts.total)장이 기다리고 있습니다."
                )
                .padding(.horizontal, 22)

                if counts.total > 0 {
                    PrimaryButton(title: "복습 시작") { build() }
                        .padding(.horizontal, 22)
                }
                Spacer()
            }
        }
        .padding(.bottom, 12)
        .task { build() }
        .onChange(of: filter) { _, _ in build() }
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            ForEach(CardQueue.Filter.allCases) { option in
                let optionCounts = CardQueue.counts(from: cards, filter: option)
                Button {
                    filter = option
                } label: {
                    Chip(
                        text: "\(option.title) \(optionCounts.total)",
                        color: filter == option ? Palette.shadow : Palette.dim,
                        isActive: filter == option
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if let current {
                Text("\(index + 1) / \(queue.count)")
                    .font(.mono(11))
                    .foregroundStyle(Palette.faint)
                    .accessibilityLabel("\(queue.count)장 중 \(index + 1)번째")
                    .id(current.id)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: - 카드

    private func cardFace(_ card: StudyCard) -> some View {
        VStack(spacing: 13) {
            Text(card.kind.directionLabel)
                .microLabel(card.kind.isWord ? Palette.listen : Palette.shadow)

            if card.kind.isAudioPrompt {
                Button { playSource(card) } label: {
                    Chip(text: "소리 듣기", color: Palette.listen, isActive: true, icon: "play.fill")
                }
                .buttonStyle(.plain)
            } else {
                Text(card.prompt)
                    .font(.system(size: card.kind == .sentence ? 22 : 29, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !isRevealed {
                Spacer()
                GhostButton(title: "정답 보기") { reveal(card) }
            } else {
                Divider().overlay(Palette.lineSoft)

                Text(card.answer)
                    .font(card.kind == .sentence ? .mono(16) : .system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.shadow)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if !card.note.isBlank {
                    Text(card.note).microLabel()
                }

                if !card.example.isBlank {
                    exampleBlock(card)
                }

                audioRow(card)

                if let source = sourceLabel(card) {
                    Text(source).microLabel()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
        .padding(.horizontal, 22)
    }

    /// 예문은 지어내지 않고 에피소드 원문을 쓴다. 해당 단어만 오렌지로 칠한다.
    private func exampleBlock(_ card: StudyCard) -> some View {
        Text(highlighted(card.example, term: card.kind == .wordProduction ? card.answer : card.prompt))
            .font(.system(size: 14))
            .foregroundStyle(Palette.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.lineSoft, lineWidth: 1)
            )
    }

    private func highlighted(_ text: String, term: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard !term.isBlank,
              let range = attributed.range(of: term, options: [.caseInsensitive])
        else { return attributed }
        attributed[range].foregroundColor = Palette.output
        attributed[range].font = .system(size: 14, weight: .semibold)
        return attributed
    }

    @ViewBuilder
    private func audioRow(_ card: StudyCard) -> some View {
        HStack(spacing: 9) {
            if card.hasAudioSegment, episode(for: card)?.localAudioURL != nil {
                Button { playSource(card) } label: {
                    Chip(
                        text: "원본 \((card.audioStart ?? 0).clockLabel)",
                        color: Palette.listen,
                        isActive: true,
                        icon: "play.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            // 섀도잉에서 남긴 녹음을 복습 중에 그대로 다시 듣는다.
            if let takeURL = card.takeURL {
                Button { playTake(takeURL) } label: {
                    Chip(text: "내 녹음", color: Palette.output, isActive: true, icon: "play.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sourceLabel(_ card: StudyCard) -> String? {
        guard let episode = episode(for: card) else { return nil }
        guard let lineIndex = card.lineIndex else { return episode.shortCode }
        return "\(episode.shortCode) · 문장 \(lineIndex + 1)"
    }

    // MARK: - 평가

    private func gradeButtons(_ card: StudyCard) -> some View {
        HStack(spacing: 7) {
            ForEach(Grade.allCases) { grade in
                Button {
                    apply(grade, to: card)
                } label: {
                    VStack(spacing: 2) {
                        Text(grade.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(color(for: grade))
                        // 누르기 전에 결과를 알 수 있어야 정직하게 고를 수 있다.
                        Text(isRevealed ? SRS.previewLabel(grade, for: card) : "—")
                            .font(.mono(10))
                            .foregroundStyle(Palette.faint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(borderColor(for: grade), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isRevealed)
                .opacity(isRevealed ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 22)
    }

    private func color(for grade: Grade) -> Color {
        switch grade {
        case .again: Palette.danger
        case .good: Palette.shadow
        default: Palette.text
        }
    }

    private func borderColor(for grade: Grade) -> Color {
        switch grade {
        case .again: Palette.danger.opacity(0.5)
        case .good: Palette.shadow.opacity(0.5)
        default: Palette.line
        }
    }

    // MARK: - 동작

    private func build() {
        queue = CardQueue.build(
            from: cards,
            filter: filter,
            newLimit: settings.dailyNewLimit,
            reviewLimit: settings.dailyReviewLimit
        )
        index = 0
        isRevealed = false
    }

    private func reveal(_ card: StudyCard) {
        withAnimation(.spring(duration: 0.35)) { isRevealed = true }
        if card.kind.isAudioPrompt { playSource(card) }
    }

    private func apply(_ grade: Grade, to card: StudyCard) {
        SRS.apply(grade, to: card)
        StudyPlanner.recordReview(context: context)
        try? context.save()

        player.pause()

        // 「다시」는 이 세션 안에서 다시 만난다.
        if grade == .again {
            queue.remove(at: index)
            queue.append(card)
        } else {
            index += 1
        }
        if index >= queue.count {
            queue = []
            index = 0
        }
        isRevealed = false
    }

    private func episode(for card: StudyCard) -> Episode? {
        guard let guid = card.episodeGUID else { return nil }
        return episodes.first { $0.guid == guid }
    }

    private func playSource(_ card: StudyCard) {
        guard let episode = episode(for: card),
              let url = episode.localAudioURL,
              let start = card.audioStart,
              let end = card.audioEnd
        else { return }
        try? player.load(url: url, owner: episode.guid)
        player.playSegment(from: start, to: end, looping: false)
    }

    private func playTake(_ url: URL) {
        try? player.load(url: url, owner: url.lastPathComponent)
        player.clearSegment()
        player.seek(to: 0)
        player.play()
    }
}
