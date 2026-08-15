import SwiftUI

// 색 토큰. 값은 design/sixmin-design.html 의 팔레트와 1:1로 맞춘다.
enum Palette {
    static let ink = Color(hex: 0x0B0E13)
    static let surface = Color(hex: 0x141922)
    static let raised = Color(hex: 0x1C222D)
    static let line = Color(hex: 0x2A3140)
    static let lineSoft = Color(hex: 0x20262F)

    static let text = Color(hex: 0xE8EBF0)
    static let dim = Color(hex: 0x8A93A4)
    static let faint = Color(hex: 0x59616F)

    static let listen = Color(hex: 0x6FB6FF)
    static let shadow = Color(hex: 0x43D9BE)
    static let output = Color(hex: 0xFF8A4C)
    static let good = Color(hex: 0x5BE08A)
    static let danger = Color(hex: 0xFF6B6B)

    /// 단계색 위에 얹는 글자색. 밝은 배경이므로 잉크를 쓴다.
    static let onAccent = Color(hex: 0x07100E)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// 시간·간격·개수처럼 자리가 흔들리면 안 되는 숫자용.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// 「LISTEN」처럼 자간을 벌린 대문자 마이크로 라벨.
    func microLabel(_ color: Color = Palette.faint) -> some View {
        self.font(.mono(11, .medium))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    func cardSurface(border: Color = Palette.line) -> some View {
        self.padding(16)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

/// 루틴 3단계. 색은 차가운 쪽에서 따뜻한 쪽으로 흐른다.
enum Stage: String, CaseIterable, Identifiable, Codable, Hashable {
    case listen, shadow, output

    var id: String { rawValue }

    var order: Int {
        switch self {
        case .listen: 0
        case .shadow: 1
        case .output: 2
        }
    }

    var number: String { String(format: "%02d", order + 1) }

    var title: String {
        switch self {
        case .listen: "듣기"
        case .shadow: "섀도잉"
        case .output: "출력"
        }
    }

    var latinTitle: String {
        switch self {
        case .listen: "Listen"
        case .shadow: "Shadow"
        case .output: "Output"
        }
    }

    var color: Color {
        switch self {
        case .listen: Palette.listen
        case .shadow: Palette.shadow
        case .output: Palette.output
        }
    }
}
