import SwiftData
import SwiftUI

/// 들은 걸 내 말로 다시 뱉는 단계. 여기서 막힌 표현이 곧 복습 카드가 되므로 저장 동선을 화면 안에 붙여 둔다.
struct OutputView: View {
    let episode: Episode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(RoutineClock.self) private var clock
    @Environment(PlayerEngine.self) private var player

    @Query(sort: \StudyCard.createdAt, order: .reverse) private var cards: [StudyCard]

    @State private var promptIndex = 0
    @State private var draft = ""
    @State private var captureMode: CaptureMode = .sentence
    @State private var koreanField = ""
    @State private var englishField = ""
    @State private var noteField = ""

    private let stage = Stage.output
    private var timer: RoutineClock.StageState { clock.state(stage) }

    /// 매일 같은 틀이라 뭘 쓸지 고민하는 시간이 사라진다.
    private static let prompts = [
        "오늘 에피소드를 **영어 세 문장**으로 요약해 보세요.",
        "에피소드 내용을 **내 경험**과 이어서 영어로 써 보세요.",
        "오늘 새로 본 표현 **3개**를 넣어 문장을 만들어 보세요.",
    ]

    private enum CaptureMode: String, CaseIterable, Identifiable {
        case sentence, word
        var id: String { rawValue }
        var title: String { self == .sentence ? "문장" : "단어" }
    }

    private var todaysCards: [StudyCard] {
        cards.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    /// 방금 섀도잉한 문장을 카드에 자동으로 연결한다.
    private var linkedLine: TranscriptLine? {
        episode.sortedLines
            .filter(\.hasTake)
            .max { ($0.latestTake?.recordedAt ?? .distantPast) < ($1.latestTake?.recordedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 13) {
                promptCard
                captureCard
                savedList
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "출력 완료", color: stage.color) { complete() }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
                .background(Palette.surface)
        }
        .screenBackground()
        .navigationTitle("출력")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Chip(text: timer.remaining.timerLabel, color: stage.color, isActive: true)
                    .monospacedDigit()
            }
        }
        .task { start() }
        .onDisappear { persist() }
        .onChange(of: clock.finishedStage) { _, finished in
            guard finished == stage else { return }
            complete()
            clock.finishedStage = nil
        }
    }

    // MARK: - 과제

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("오늘의 과제 · \(promptIndex + 1) / \(Self.prompts.count)").microLabel(stage.color)

            Text(.init(Self.prompts[promptIndex]))
                .font(.system(size: 16))
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(8)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )

            HStack {
                Text("\(draft.split(whereSeparator: \.isNewline).count)줄").microLabel()
                Spacer()
                Button {
                    promptIndex = (promptIndex + 1) % Self.prompts.count
                    draft = ""
                } label: {
                    Chip(text: "다음 과제", color: Palette.dim, icon: "arrow.right")
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface(border: stage.color.opacity(0.34))
    }

    // MARK: - 막힌 표현 저장

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "막힌 표현 저장")
                Spacer()
                if let linkedLine {
                    Chip(text: "문장 \(linkedLine.index + 1) 연결됨", color: Palette.shadow, isActive: true)
                }
            }

            Picker("종류", selection: $captureMode) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // 한국어를 먼저 두는 건 의도적이다. 못 옮긴 순간이 기록할 가치가 있는 유일한 순간이니까.
            field(
                placeholder: captureMode == .sentence ? "쓰다가 막힌 한국어를 그대로" : "뜻 (한국어)",
                text: $koreanField
            )
            field(
                placeholder: captureMode == .sentence ? "틀려도 좋으니 영어로" : "영단어 · 표현",
                text: $englishField,
                monospaced: true
            )
            if captureMode == .word {
                field(placeholder: "품사나 짧은 설명 (선택)", text: $noteField)
            }

            Button { save() } label: {
                Chip(
                    text: captureMode == .sentence ? "문장 카드로 저장" : "단어 카드로 저장",
                    color: canSave ? Palette.output : Palette.faint,
                    isActive: canSave
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)

            if captureMode == .word {
                Text(wordCardHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardSurface()
    }

    private var wordCardHint: String {
        var kinds = ["영어 → 뜻"]
        if settings.makeProductionCards { kinds.append("뜻 → 영어") }
        if settings.makeListeningCards { kinds.append("듣고 맞히기") }
        return "카드 \(kinds.count)장이 만들어집니다 — \(kinds.joined(separator: ", ")). 각각 간격을 따로 셉니다."
    }

    private func field(placeholder: String, text: Binding<String>, monospaced: Bool = false) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .font(monospaced ? .mono(13) : .system(size: 14))
            .lineLimit(1...4)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            )
    }

    private var canSave: Bool {
        !koreanField.isBlank && !englishField.isBlank
    }

    // MARK: - 오늘 저장한 카드

    @ViewBuilder
    private var savedList: some View {
        if !todaysCards.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(text: "오늘 저장한 카드 \(todaysCards.count)")
                    .padding(.bottom, 4)

                ForEach(todaysCards.prefix(6)) { card in
                    HStack {
                        Text(card.kind == .sentence ? card.prompt : "\(card.prompt) — \(card.answer)")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Chip(text: card.kind.label)
                    }
                    .padding(.vertical, 11)

                    Divider().overlay(Palette.lineSoft)
                }
            }
        }
    }

    // MARK: - 동작

    private func save() {
        guard canSave else { return }
        let line = linkedLine

        switch captureMode {
        case .sentence:
            let card = CardFactory.sentenceCard(
                korean: koreanField,
                english: englishField,
                episode: episode,
                line: line
            )
            context.insert(card)

        case .word:
            let cards = CardFactory.wordCards(
                word: englishField,
                meaning: koreanField,
                note: noteField,
                episode: episode,
                line: line,
                includeProduction: settings.makeProductionCards,
                includeListening: settings.makeListeningCards
            )
            for card in cards { context.insert(card) }
        }

        try? context.save()
        koreanField = ""
        englishField = ""
        noteField = ""

        Task { await NotificationScheduler.refresh(context: context, settings: settings) }
    }

    private func start() {
        player.pause()
        if !clock.state(stage).isRunning, clock.state(stage).remaining > 0 {
            clock.toggle(stage)
        }
    }

    private func persist() {
        clock.pause(stage)
        StudyPlanner.recordStudyTime(clock.drainUnsavedSeconds(stage), stage: stage, context: context)
        try? context.save()
    }

    private func complete() {
        persist()
        StudyPlanner.markStage(stage, done: true, context: context)
        try? context.save()
        Task { await NotificationScheduler.refresh(context: context, settings: settings) }
        dismiss()
    }
}
