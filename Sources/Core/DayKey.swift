import Foundation

/// 하루를 `yyyy-MM-dd` 문자열 하나로 다룬다. 히트맵과 루틴 기록이 전부 이 키에 매달려 있다.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func key(_ date: Date = .now) -> String {
        formatter.string(from: date)
    }

    static var today: String { key() }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    static func adding(_ days: Int, to key: String) -> String {
        guard let date = date(from: key),
              let moved = Calendar.current.date(byAdding: .day, value: days, to: date)
        else { return key }
        return self.key(moved)
    }

    /// `from`에서 `to`까지 며칠인지. 같은 날이면 0.
    static func days(from: String, to: String) -> Int {
        guard let a = date(from: from), let b = date(from: to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func startOfDay(_ date: Date = .now) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// 오늘 00:00에서 `minutes`분 뒤. 이미 지났으면 내일 같은 시각.
    static func nextOccurrence(ofMinuteOfDay minutes: Int, after now: Date = .now) -> Date {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: now)
        let today = base.addingTimeInterval(TimeInterval(minutes * 60))
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }

    static func timeLabel(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}

extension Double {
    /// 초 → `1:24`. 오디오 위치 표기 전용.
    var clockLabel: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Int {
    /// 초 → `17:42`. 루틴 타이머 표기 전용이라 분 자리를 두 칸으로 고정한다.
    var timerLabel: String {
        let clamped = Swift.max(0, self)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }
}
