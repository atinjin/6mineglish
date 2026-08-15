import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var context

    @Query private var logs: [RoutineLog]
    @Query private var cards: [StudyCard]
    @Query private var episodes: [Episode]

    private var levels: [String: Int] {
        Dictionary(logs.map { ($0.dayKey, $0.completedStages) }, uniquingKeysWith: { first, _ in first })
    }

    private var logsByDay: [String: RoutineLog] {
        Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var totalHours: Double {
        Double(logs.reduce(0) { $0 + $1.totalSeconds }) / 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 13) {
                    streakCard
                    tiles
                    weekCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("기록")
        }
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\(StudyPlanner.streak(context))")
                    .font(.mono(38, .bold))
                    .foregroundStyle(Palette.output)
                Text("일 연속")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("최장 \(StudyPlanner.longestStreak(context))일").microLabel()
            }

            HeatmapView(levels: levels)

            HeatmapLegend()
        }
        .cardSurface()
    }

    private var tiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("총 학습", value: String(format: "%.0f", totalHours), unit: "시간")
            tile("끝낸 에피소드", value: "\(episodes.filter(\.isCompleted).count)")
            tile("보관 카드", value: "\(cards.count)")
            // 간격이 21일을 넘긴 카드. 진짜로 외워진 양에 가장 가깝다.
            tile("성숙 카드", value: "\(cards.filter(\.isMature).count)", color: Palette.good)
        }
    }

    private func tile(_ label: String, value: String, unit: String? = nil, color: Color = Palette.text) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.mono(24, .bold))
                    .foregroundStyle(color)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.dim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        )
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionLabel(text: "최근 7일 · 단계별")
            WeekStageGrid(logs: logsByDay)
        }
        .cardSurface()
    }
}
