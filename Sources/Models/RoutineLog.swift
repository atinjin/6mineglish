import Foundation
import SwiftData

/// 하루치 루틴 기록. 히트맵의 한 칸이자, 연속 일수의 근거.
@Model
final class RoutineLog {
    @Attribute(.unique) var dayKey: String

    var listenDone: Bool
    var shadowDone: Bool
    var outputDone: Bool

    var listenSeconds: Int
    var shadowSeconds: Int
    var outputSeconds: Int

    var reviewedCount: Int
    var episodeGUID: String?

    init(dayKey: String) {
        self.dayKey = dayKey
        self.listenDone = false
        self.shadowDone = false
        self.outputDone = false
        self.listenSeconds = 0
        self.shadowSeconds = 0
        self.outputSeconds = 0
        self.reviewedCount = 0
    }

    func isDone(_ stage: Stage) -> Bool {
        switch stage {
        case .listen: listenDone
        case .shadow: shadowDone
        case .output: outputDone
        }
    }

    func setDone(_ stage: Stage, _ value: Bool) {
        switch stage {
        case .listen: listenDone = value
        case .shadow: shadowDone = value
        case .output: outputDone = value
        }
    }

    func addSeconds(_ seconds: Int, to stage: Stage) {
        guard seconds > 0 else { return }
        switch stage {
        case .listen: listenSeconds += seconds
        case .shadow: shadowSeconds += seconds
        case .output: outputSeconds += seconds
        }
    }

    /// 0~3. 히트맵 농도가 이 값을 그대로 쓴다 — 절반만 한 날도 흔적이 남는다.
    var completedStages: Int {
        [listenDone, shadowDone, outputDone].filter { $0 }.count
    }

    var isComplete: Bool { completedStages == 3 }

    var totalSeconds: Int { listenSeconds + shadowSeconds + outputSeconds }
}
