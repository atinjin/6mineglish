import Combine
import SwiftData
import SwiftUI

/// 단어와 뜻을 쌍으로 붙여 보는 빠른 확인. 카드 넘기기가 무거운 날의 준비운동이다.
struct PairMatchView: View {
    @Environment(\.modelContext) private var context

    @Query private var cards: [StudyCard]

    @State private var tiles: [Tile] = []
    @State private var selectedID: UUID?
    @State private var wrongIDs: Set<UUID> = []
    @State private var matchedPairs = 0
    @State private var missedPairs = 0
    @State private var elapsed = 0
    @State private var isFinished = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private struct Tile: Identifiable, Equatable {
        let id = UUID()
        let pairID: UUID
        let text: String
        /// 왼쪽 열은 영어, 오른쪽 열은 뜻. 열이 고정이라 어느 쪽을 누를지 헷갈리지 않는다.
        let isEnglish: Bool
        var isMatched = false
    }

    private var totalPairs: Int { tiles.count / 2 }

    var body: some View {
        VStack(spacing: 13) {
            if tiles.isEmpty {
                Spacer()
                EmptyHint(
                    icon: "square.grid.2x2",
                    title: isFinished ? "짝 맞추기 끝" : "짝 맞출 단어가 없습니다",
                    message: isFinished
                        ? "\(totalPairsAtStart)쌍 중 \(missedPairs)쌍을 놓쳤습니다. 놓친 단어는 오늘 복습 큐로 돌아갔습니다."
                        : "출력 단계에서 단어를 저장하면 여기에 모입니다."
                )
                .padding(.horizontal, 22)

                Button { build() } label: {
                    Chip(text: "다시 시작", color: Palette.shadow, isActive: true, icon: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                statusBar
                grid
                hint
                Spacer(minLength: 0)
            }
        }
        .task { build() }
        .onReceive(ticker) { _ in
            guard !tiles.isEmpty else { return }
            elapsed += 1
        }
    }

    @State private var totalPairsAtStart = 0

    private var statusBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(matchedPairs) / \(totalPairsAtStart) 쌍 맞춤")
                    .font(.mono(11))
                    .foregroundStyle(Palette.faint)
                Spacer()
                if missedPairs > 0 {
                    Chip(text: "놓친 짝 \(missedPairs)", color: Palette.danger, isActive: true)
                }
                Chip(text: elapsed.timerLabel, color: Palette.dim)
            }
            StageProgressRail(
                stage: .shadow,
                progress: totalPairsAtStart > 0 ? Double(matchedPairs) / Double(totalPairsAtStart) : 0
            )
        }
        .padding(.horizontal, 22)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            ForEach(tiles) { tile in
                Button {
                    tap(tile)
                } label: {
                    Text(tile.text)
                        .font(.system(size: 15))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(foreground(tile))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                        .background(background(tile), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(border(tile), lineWidth: 1)
                        )
                        .opacity(tile.isMatched ? 0.42 : 1)
                }
                .buttonStyle(.plain)
                .disabled(tile.isMatched)
                .accessibilityLabel("\(tile.isEnglish ? "영어" : "뜻") \(tile.text)\(tile.isMatched ? ", 맞춤" : "")")
            }
        }
        .padding(.horizontal, 22)
        .animation(.easeOut(duration: 0.2), value: tiles)
        .sensoryFeedback(.error, trigger: missedPairs)
        .sensoryFeedback(.success, trigger: matchedPairs)
    }

    private var hint: some View {
        Text("왼쪽 영어를 누르고 오른쪽 뜻을 누릅니다. 틀린 짝은 오늘 복습 큐로 되돌아가고, 여기서의 정답 여부가 간격을 바꾸지는 않습니다.")
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.faint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
    }

    // MARK: - 색

    private func foreground(_ tile: Tile) -> Color {
        if tile.isMatched { return Palette.good }
        if wrongIDs.contains(tile.id) { return Palette.danger }
        if selectedID == tile.id { return Palette.shadow }
        return Palette.text
    }

    private func background(_ tile: Tile) -> Color {
        selectedID == tile.id ? Palette.shadow.opacity(0.1) : Palette.raised
    }

    private func border(_ tile: Tile) -> Color {
        if tile.isMatched { return Palette.good.opacity(0.45) }
        if wrongIDs.contains(tile.id) { return Palette.danger }
        if selectedID == tile.id { return Palette.shadow }
        return Palette.line
    }

    // MARK: - 동작

    private func build() {
        let candidates = CardQueue.pairCandidates(from: cards)
        guard !candidates.isEmpty else {
            tiles = []
            totalPairsAtStart = 0
            return
        }

        let english = candidates.map { Tile(pairID: $0.id, text: $0.prompt, isEnglish: true) }
        let korean = candidates.map { Tile(pairID: $0.id, text: $0.answer, isEnglish: false) }.shuffled()

        // 왼쪽 열은 영어, 오른쪽 열은 뜻 — 순서만 섞는다.
        tiles = zip(english, korean).flatMap { pair in [pair.0, pair.1] }
        totalPairsAtStart = candidates.count
        matchedPairs = 0
        missedPairs = 0
        elapsed = 0
        selectedID = nil
        wrongIDs = []
        isFinished = false
    }

    private func tap(_ tile: Tile) {
        guard !tile.isMatched else { return }
        wrongIDs = []

        guard let selectedID, let firstIndex = tiles.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = tile.id
            return
        }

        if selectedID == tile.id {
            self.selectedID = nil
            return
        }

        let first = tiles[firstIndex]
        // 같은 열끼리는 짝이 아니다.
        guard first.isEnglish != tile.isEnglish else {
            self.selectedID = tile.id
            return
        }

        guard let secondIndex = tiles.firstIndex(where: { $0.id == tile.id }) else { return }

        if first.pairID == tile.pairID {
            tiles[firstIndex].isMatched = true
            tiles[secondIndex].isMatched = true
            matchedPairs += 1
            self.selectedID = nil
            if tiles.allSatisfy(\.isMatched) { finish() }
        } else {
            // 정답을 알려주지 않고 다시 시도하게 둔다.
            missedPairs += 1
            wrongIDs = [first.id, tile.id]
            self.selectedID = nil
            requeue(pairID: first.pairID)
            requeue(pairID: tile.pairID)
        }
    }

    /// 틀린 항목만 그날 복습 큐로 되돌린다. 간격 계산에는 넣지 않는다.
    private func requeue(pairID: UUID) {
        guard let card = cards.first(where: { $0.id == pairID }) else { return }
        card.dueAt = min(card.dueAt, .now)
        try? context.save()
    }

    private func finish() {
        isFinished = true
        tiles = []
    }
}
