import SwiftUI

/// 완료 여부가 아니라 완료 정도를 담는다. 절반만 한 날도 흔적이 남아야 다시 돌아오기 쉽다.
struct HeatmapView: View {
    /// dayKey → 완료한 단계 수(0~3)
    var levels: [String: Int]
    var weeks: Int = 20
    var cell: CGFloat = 11
    var spacing: CGFloat = 3

    private var columns: [[String]] {
        let calendar = Calendar.current
        let today = Date()
        // 이번 주 일요일을 오른쪽 끝 열로 둔다.
        let weekday = calendar.component(.weekday, from: today) - 1
        let lastColumnStart = calendar.date(byAdding: .day, value: -weekday, to: today) ?? today

        return (0..<weeks).reversed().map { offset in
            let columnStart = calendar.date(byAdding: .day, value: -offset * 7, to: lastColumnStart) ?? lastColumnStart
            return (0..<7).map { day in
                let date = calendar.date(byAdding: .day, value: day, to: columnStart) ?? columnStart
                return DayKey.key(date)
            }
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(week, id: \.self) { dayKey in
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(fill(for: levels[dayKey] ?? 0))
                                .frame(width: cell, height: cell)
                                .accessibilityLabel(accessibilityLabel(dayKey))
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .defaultScrollAnchor(.trailing)
    }

    /// 마지막 단계의 색을 쓴다 — 하루가 끝까지 갔다는 뜻이니까.
    private func fill(for level: Int) -> Color {
        switch level {
        case 1: Palette.output.opacity(0.28)
        case 2: Palette.output.opacity(0.58)
        case 3: Palette.output
        default: Palette.raised
        }
    }

    private func accessibilityLabel(_ dayKey: String) -> String {
        let level = levels[dayKey] ?? 0
        return level == 0 ? "\(dayKey), 기록 없음" : "\(dayKey), \(level)단계 완료"
    }
}

struct HeatmapLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("적음").microLabel()
            ForEach([0, 1, 2, 3], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(level == 0 ? Palette.raised : Palette.output.opacity(level == 1 ? 0.28 : level == 2 ? 0.58 : 1))
                    .frame(width: 11, height: 11)
            }
            Text("3단계 완료").microLabel()
        }
        .accessibilityHidden(true)
    }
}

/// 하루당 점 세 개 — 어느 단계에서 자꾸 멈추는지가 보인다.
struct WeekStageGrid: View {
    var logs: [String: RoutineLog]

    private var days: [String] {
        (0..<7).reversed().map { DayKey.adding(-$0, to: DayKey.today) }
    }

    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        HStack {
            ForEach(days, id: \.self) { dayKey in
                VStack(spacing: 5) {
                    ForEach(Stage.allCases) { stage in
                        Circle()
                            .fill(logs[dayKey]?.isDone(stage) == true ? stage.color : Palette.line)
                            .frame(width: 9, height: 9)
                    }
                    Text(weekdayLabel(dayKey))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.faint)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dayKey), \(logs[dayKey]?.completedStages ?? 0)단계 완료")
            }
        }
    }

    private func weekdayLabel(_ dayKey: String) -> String {
        guard let date = DayKey.date(from: dayKey) else { return "" }
        let index = Calendar.current.component(.weekday, from: date) - 1
        return Self.weekdaySymbols[max(0, min(6, index))]
    }
}
