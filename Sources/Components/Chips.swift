import SwiftUI

struct Chip: View {
    var text: String
    var color: Color = Palette.dim
    var isActive = false
    var icon: String?

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.mono(11))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(
            Capsule().strokeBorder(isActive ? color : Palette.line, lineWidth: 1)
        )
    }
}

struct SectionLabel: View {
    var text: String
    var color: Color = Palette.faint

    var body: some View {
        Text(text).microLabel(color)
    }
}

struct PrimaryButton: View {
    var title: String
    var color: Color = Palette.shadow
    var isEnabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color.opacity(isEnabled ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .foregroundStyle(Palette.onAccent)
        }
        .disabled(!isEnabled)
    }
}

struct GhostButton: View {
    var title: String
    var color: Color = Palette.text
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                )
        }
    }
}

/// 루틴 진행 중인 단계를 알리는 얇은 레일. 색이 곧 단계다.
struct StageProgressRail: View {
    var stage: Stage
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.line)
                Capsule()
                    .fill(stage.color)
                    .frame(width: geometry.size.width * progress.clamped01)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// 상태를 아이콘 여러 개 대신 3pt 세로 막대 하나로 읽힌다.
struct StatusBar: View {
    var color: Color
    var height: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 3, height: height)
    }
}

struct EmptyHint: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.faint)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.dim)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Palette.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Palette.line)
        )
    }
}
