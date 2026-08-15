import Foundation
import Observation
import SwiftUI

/// 3단계 타이머를 하나의 틱으로 굴린다. 화면을 오가도 남은 시간이 유지되도록 앱 수명 동안 살아 있다.
@MainActor
@Observable
final class RoutineClock {
    struct StageState {
        var total: Int
        var remaining: Int
        var isRunning: Bool
        /// 아직 기록에 반영하지 않은 경과 시간.
        var unsavedSeconds: Int

        var elapsed: Int { max(0, total - remaining) }
        var progress: Double { total > 0 ? Double(elapsed) / Double(total) : 0 }
    }

    private(set) var states: [Stage: StageState] = [:]
    /// 타이머가 0에 닿은 단계. 뷰가 완료 처리하고 nil로 되돌린다.
    var finishedStage: Stage?

    @ObservationIgnored private var ticker: Timer?

    init(settings: AppSettings? = nil) {
        for stage in Stage.allCases {
            let minutes = settings?.minutes(for: stage) ?? 20
            states[stage] = StageState(
                total: minutes * 60,
                remaining: minutes * 60,
                isRunning: false,
                unsavedSeconds: 0
            )
        }
    }

    func state(_ stage: Stage) -> StageState {
        states[stage] ?? StageState(total: 0, remaining: 0, isRunning: false, unsavedSeconds: 0)
    }

    /// 설정에서 분이 바뀌면 반영한다. 이미 돌고 있는 단계는 건드리지 않는다.
    func syncDurations(with settings: AppSettings) {
        for stage in Stage.allCases {
            let total = settings.minutes(for: stage) * 60
            guard var current = states[stage], current.total != total else { continue }
            guard !current.isRunning, current.remaining == current.total else {
                current.total = total
                states[stage] = current
                continue
            }
            current.total = total
            current.remaining = total
            states[stage] = current
        }
    }

    func toggle(_ stage: Stage) {
        guard var current = states[stage] else { return }
        current.isRunning.toggle()
        states[stage] = current
        updateTicker()
    }

    func pause(_ stage: Stage) {
        guard var current = states[stage], current.isRunning else { return }
        current.isRunning = false
        states[stage] = current
        updateTicker()
    }

    func pauseAll() {
        for stage in Stage.allCases {
            guard var current = states[stage] else { continue }
            current.isRunning = false
            states[stage] = current
        }
        updateTicker()
    }

    func reset(_ stage: Stage) {
        guard var current = states[stage] else { return }
        current.isRunning = false
        current.remaining = current.total
        states[stage] = current
        updateTicker()
    }

    /// 기록에 반영할 초를 꺼내면서 카운터를 비운다.
    func drainUnsavedSeconds(_ stage: Stage) -> Int {
        guard var current = states[stage] else { return 0 }
        let seconds = current.unsavedSeconds
        current.unsavedSeconds = 0
        states[stage] = current
        return seconds
    }

    private func updateTicker() {
        let anyRunning = states.values.contains(where: \.isRunning)
        if anyRunning, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !anyRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func tick() {
        for stage in Stage.allCases {
            guard var current = states[stage], current.isRunning else { continue }
            current.remaining = max(0, current.remaining - 1)
            current.unsavedSeconds += 1

            if current.remaining == 0 {
                current.isRunning = false
                states[stage] = current
                finishedStage = stage
            } else {
                states[stage] = current
            }
        }
        updateTicker()
    }
}
