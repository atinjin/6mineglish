import SwiftUI

/// 재생된 구간은 진하고 남은 구간은 22%. 얼마나 남았는지를 숫자보다 먼저 알게 한다.
struct WaveformView: View {
    var samples: [Float]
    var progress: Double
    var color: Color
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            let count = max(samples.count, 1)
            let played = Int((Double(count) * progress.clamped01).rounded())

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(samples.enumerated()), id: \.offset) { index, value in
                    Capsule(style: .continuous)
                        .fill(color)
                        .opacity(index < played ? 1 : 0.22)
                        .frame(
                            width: barWidth,
                            height: max(2, CGFloat(value) * geometry.size.height)
                        )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

/// 원본은 위·블루, 내 목소리는 아래·오렌지. 이 배치는 앱 전체에서 고정이다.
struct WaveformComparison: View {
    var source: [Float]
    var mine: [Float]?
    var sourceDuration: Double
    var mineDuration: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            row(label: "원본", samples: source, color: Palette.listen)

            if let mine {
                row(label: "내 말", samples: mine, color: Palette.output)
            } else {
                HStack(spacing: 9) {
                    Text("내 말").microLabel(Palette.faint).frame(width: 34, alignment: .leading)
                    Text("아직 녹음이 없습니다")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                    Spacer()
                }
                .frame(height: 30)
            }

            if let mineDuration, sourceDuration > 0 {
                let delta = mineDuration - sourceDuration
                HStack {
                    Spacer()
                    Text("길이 차")
                        .microLabel(Palette.faint)
                    Text(String(format: "%@%.1fs", delta >= 0 ? "+" : "", delta))
                        .font(.mono(11, .semibold))
                        .foregroundStyle(abs(delta) < 0.4 ? Palette.good : Palette.output)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("내 녹음이 원본보다 \(String(format: "%.1f", abs(delta)))초 \(delta >= 0 ? "깁니다" : "짧습니다")")
            }
        }
    }

    private func row(label: String, samples: [Float], color: Color) -> some View {
        HStack(spacing: 9) {
            Text(label).microLabel(color).frame(width: 34, alignment: .leading)
            WaveformView(samples: samples, progress: 1, color: color)
                .frame(height: 30)
        }
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
